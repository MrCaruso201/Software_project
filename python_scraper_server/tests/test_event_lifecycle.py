import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, patch

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from db.models import Base, Event
from events.lifecycle import finish_past_events, close_expired_events


class EventLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine("sqlite://")
        Base.metadata.create_all(self.engine)
        self.factory = sessionmaker(bind=self.engine)
        self.session_patch = patch("events.lifecycle.SessionLocal", self.factory)
        self.session_patch.start()

    def tearDown(self):
        self.session_patch.stop()
        self.engine.dispose()

    def add_event(self, date, status="scheduled"):
        with self.factory() as db:
            event = Event(title="Race", location="Track", event_date=date, status=status)
            db.add(event)
            db.commit()
            return event.id

    def test_closes_only_events_at_least_two_days_old(self):
        now = datetime(2026, 9, 17, 14, 30)
        old = [self.add_event(now - timedelta(days=2), status)
               for status in ("scheduled", "started")]
        recent = self.add_event(now - timedelta(days=1))
        future = self.add_event(now + timedelta(days=1))
        self.add_event(now - timedelta(days=3), "finished")
        self.assertEqual(set(finish_past_events(now=now)), set(old))
        self.assertEqual(finish_past_events(now=now), [])
        with self.factory() as db:
            self.assertTrue(all(db.get(Event, id).status == "finished" for id in old))
            self.assertEqual(db.get(Event, recent).status, "scheduled")
            self.assertEqual(db.get(Event, future).status, "scheduled")

    def test_exact_48_hour_boundary_including_daylight_saving_changes(self):
        for start in (datetime(2026, 1, 15, 14, 30), datetime(2026, 9, 15, 14, 30),
                      datetime(2026, 3, 28, 14, 30), datetime(2026, 10, 24, 14, 30)):
            with self.subTest(start=start):
                event_id = self.add_event(start)
                deadline = start + timedelta(hours=48)
                self.assertEqual(finish_past_events(now=deadline - timedelta(seconds=1)), [])
                self.assertEqual(finish_past_events(now=deadline.replace(tzinfo=timezone.utc)), [event_id])

    def test_aware_now_is_converted_to_utc(self):
        event_id = self.add_event(datetime(2026, 9, 15, 14, 30))
        local_deadline = datetime(2026, 9, 17, 16, 30, tzinfo=timezone(timedelta(hours=2)))
        self.assertEqual(finish_past_events(now=local_deadline - timedelta(seconds=1)), [])
        self.assertEqual(finish_past_events(now=local_deadline), [event_id])


class EventExpirationNotificationTests(unittest.IsolatedAsyncioTestCase):
    async def test_notifies_clients_after_scan(self):
        with patch("events.lifecycle.finish_past_events", return_value=[7]) as scan, \
             patch("events.lifecycle.broadcast_to_event", new_callable=AsyncMock) as broadcast:
            await close_expired_events()
        scan.assert_called_once_with()
        broadcast.assert_awaited_once_with(7, {"type": "event_update"})
