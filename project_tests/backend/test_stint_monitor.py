import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi import BackgroundTasks

from db.models import Base, Event, LiveKartAssignment, RacePenalty, PenaltyType
from live.stint_monitor import assess_stint, scan_stints
from live.router import update_kart_pit_status, delete_penalty
from live.schemas import KartPitUpdate


class StintPenaltyTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine("sqlite://")
        Base.metadata.create_all(self.engine)
        self.factory = sessionmaker(bind=self.engine, autoflush=False)
        self.db = self.factory()
        self.db.add(PenaltyType(code="stint_time", name="Stint", action="time_added", default_seconds=42))
        self.now = datetime.now(timezone.utc).replace(tzinfo=None)
        self.event = Event(title="Test", event_date=self.now, location="Track",
                           max_stint_duration=1, race_status="running")
        self.db.add(self.event)
        self.db.flush()
        self.kart = LiveKartAssignment(event_id=self.event.id, team_id="team", kart_number=7,
                                      stint_last_resume=self.now - timedelta(seconds=60))
        self.db.add(self.kart)
        self.db.commit()

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def test_threshold_once_and_admin_deletion(self):
        self.assertFalse(assess_stint(self.db, self.event, self.kart, self.now))
        self.assertTrue(assess_stint(self.db, self.event, self.kart, self.now + timedelta(seconds=1)))
        self.db.commit()
        penalty = self.db.query(RacePenalty).one()
        self.assertEqual((penalty.penalty_type, penalty.seconds), ("stint_time", 42))
        self.assertIn("+42s", penalty.note)
        delete_penalty(self.event.id, penalty.id, BackgroundTasks(), {"role": "admin"}, self.db, None)
        self.assertFalse(assess_stint(self.db, self.event, self.kart, self.now + timedelta(seconds=30)))
        self.assertEqual(self.db.query(RacePenalty).count(), 0)

    def test_pit_entry_checks_and_next_stint_rearms(self):
        self.kart.stint_last_resume = self.now - timedelta(seconds=65)
        self.db.commit()
        tasks = BackgroundTasks()
        update_kart_pit_status(self.event.id, 7, KartPitUpdate(is_in_pit=True), tasks,
                              {"role": "admin"}, self.db, None)
        self.assertEqual(self.db.query(RacePenalty).one().seconds, 42)
        self.assertTrue(self.kart.stint_penalty_assessed)
        self.assertTrue(any(t.args[1].get("change") == "penalties" for t in tasks.tasks))
        update_kart_pit_status(self.event.id, 7, KartPitUpdate(is_in_pit=False), BackgroundTasks(),
                              {"role": "admin"}, self.db, None)
        self.assertFalse(self.kart.stint_penalty_assessed)
        self.assertTrue(assess_stint(self.db, self.event, self.kart,
                                   self.kart.stint_last_resume + timedelta(seconds=61)))
        self.db.commit()
        self.assertEqual(self.db.query(RacePenalty).count(), 2)

    def test_pause_and_disabled_limit(self):
        self.event.race_status = "paused"
        self.assertFalse(assess_stint(self.db, self.event, self.kart, self.now + timedelta(hours=1)))
        self.event.race_status = "running"
        for limit in (None, 0, -1):
            self.event.max_stint_duration = limit
            self.assertFalse(assess_stint(self.db, self.event, self.kart, self.now + timedelta(hours=1)))

    def test_stale_worker_cannot_duplicate_penalty(self):
        other = self.factory()
        try:
            stale = other.get(LiveKartAssignment, self.kart.id)
            stale_event = other.get(Event, self.event.id)
            later = self.now + timedelta(seconds=5)
            self.assertTrue(assess_stint(self.db, self.event, self.kart, later))
            self.db.commit()
            self.assertFalse(assess_stint(other, stale_event, stale, later))
            other.commit()
            self.assertEqual(self.db.query(RacePenalty).count(), 1)
        finally:
            other.close()

    def test_scan_persists_across_sessions(self):
        self.kart.stint_last_resume = self.now - timedelta(seconds=65)
        self.db.commit()
        with patch("live.stint_monitor.SessionLocal", self.factory):
            self.assertEqual(scan_stints(), {self.event.id})
            self.assertEqual(scan_stints(), set())
        self.assertEqual(self.db.query(RacePenalty).count(), 1)


if __name__ == "__main__":
    unittest.main()
