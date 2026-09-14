import unittest
from datetime import datetime
from unittest.mock import patch

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from pydantic import ValidationError

from db.database import _seed_penalty_types
from db.models import Base, Event, PenaltyType, RacePenalty
from live.schemas import PenaltyTypeUpdate, PenaltyCreate


class PenaltyThresholdValidationTests(unittest.TestCase):
    def test_rejects_invalid_thresholds(self):
        for value in (-3, -1, 0, 1.5, True, "invalid"):
            with self.subTest(value=value), self.assertRaises(ValidationError):
                PenaltyTypeUpdate(warning_threshold=value)

    def test_accepts_positive_thresholds_and_unchanged_value(self):
        for value in (1, 3, 100, None):
            self.assertEqual(PenaltyTypeUpdate(warning_threshold=value).warning_threshold, value)
        self.assertIsNone(PenaltyTypeUpdate().warning_threshold)


class PenaltyConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine("sqlite://")
        Base.metadata.create_all(self.engine)
        self.factory = sessionmaker(bind=self.engine, autoflush=False)
        self.db = self.factory()

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def seed(self):
        with patch("db.database.SessionLocal", self.factory):
            _seed_penalty_types()
        self.db.expire_all()

    def test_restart_preserves_custom_seconds_and_thresholds(self):
        self.seed()
        self.db.query(PenaltyType).filter_by(code="stint_time").one().default_seconds = 47
        self.db.query(PenaltyType).filter_by(code="warning_track_limits").one().warning_threshold = 5
        self.db.query(PenaltyType).filter_by(code="warning_aggressive_driving").one().warning_threshold = None
        self.db.commit()
        self.seed()
        self.assertEqual(self.db.query(PenaltyType).filter_by(code="stint_time").one().default_seconds, 47)
        self.assertEqual(self.db.query(PenaltyType).filter_by(code="warning_track_limits").one().warning_threshold, 5)
        self.assertIsNone(self.db.query(PenaltyType).filter_by(code="warning_aggressive_driving").one().warning_threshold)

    def test_legacy_migration_preserves_history_and_configuration(self):
        self.db.add(PenaltyType(code="track_limits_10s", name="Old", action="time_added", default_seconds=23))
        event = Event(title="Test", event_date=datetime.now(), location="Track")
        self.db.add(event)
        self.db.flush()
        self.db.add(RacePenalty(event_id=event.id, kart_number=7, penalty_type="track_limits_10s", seconds=10))
        self.db.commit()
        self.seed()
        self.seed()
        self.assertEqual(self.db.query(PenaltyType).filter_by(code="track_limits_10s").count(), 0)
        self.assertEqual(self.db.query(PenaltyType).filter_by(code="track_limits").one().default_seconds, 23)
        penalty = self.db.query(RacePenalty).one()
        self.assertEqual((penalty.penalty_type, penalty.seconds), ("track_limits", 10))
        self.assertEqual(self.db.query(PenaltyType).filter_by(code="warning_track_limits").one().auto_penalty_code, "track_limits")

    def test_duplicate_codes_keep_current_configuration(self):
        self.seed()
        self.db.query(PenaltyType).filter_by(code="track_limits").one().default_seconds = 29
        self.db.add(PenaltyType(code="track_limits_10s", name="Old", action="time_added", default_seconds=17))
        self.db.commit()
        self.seed()
        self.seed()
        self.assertEqual(self.db.query(PenaltyType).filter_by(code="track_limits_10s").count(), 0)
        self.assertEqual(self.db.query(PenaltyType).filter_by(code="track_limits").one().default_seconds, 29)


class PenaltySecondsValidationTests(unittest.TestCase):
    def test_rejects_negative_and_non_integer_seconds(self):
        for value in (-10, -1, 1.5, True, "invalid"):
            for model, data in ((PenaltyTypeUpdate, {"default_seconds": value}),
                                (PenaltyCreate, {"kart_number": 7, "penalty_type": "custom", "seconds": value})):
                with self.subTest(model=model.__name__, value=value), self.assertRaises(ValidationError):
                    model(**data)

    def test_accepts_zero_positive_and_optional_seconds(self):
        for value in (None, 0, 1, 30):
            self.assertEqual(PenaltyTypeUpdate(default_seconds=value).default_seconds, value)
            self.assertEqual(PenaltyCreate(kart_number=7, penalty_type="custom", seconds=value).seconds, value)
