import unittest
from datetime import datetime

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from db.models import Base, Event, LapTime
from results.router import router


class LapStatsTests(unittest.TestCase):
    def test_unique_route_and_per_kart_threshold(self):
        routes = [r for r in router.routes if r.path == '/events/{event_id}/lap-stats' and 'GET' in r.methods]
        self.assertEqual(len(routes), 1)
        engine = create_engine('sqlite://')
        Base.metadata.create_all(engine)
        try:
            with sessionmaker(bind=engine)() as db:
                event = Event(title='Test', event_date=datetime.now(), location='Track')
                db.add(event)
                db.flush()
                for kart, times in [(1, [60000, 70000, 100000]), (2, [100000, 120000, 160000])]:
                    for lap, duration in enumerate(times, start=1):
                        db.add(LapTime(event_id=event.id, kart_number=kart, lap_number=lap, lap_time_ms=duration))
                db.commit()
                stats = {r.kart_number: r for r in routes[0].endpoint(event.id, {}, db)}
                self.assertEqual((stats[1].best_lap_ms, stats[1].worst_lap_ms, stats[1].avg_lap_ms, stats[1].laps_counted), (60000, 70000, 65000, 2))
                self.assertEqual((stats[2].best_lap_ms, stats[2].worst_lap_ms, stats[2].avg_lap_ms, stats[2].laps_counted), (100000, 120000, 110000, 2))
                self.assertEqual(routes[0].endpoint(event.id + 1, {}, db), [])
        finally:
            engine.dispose()
