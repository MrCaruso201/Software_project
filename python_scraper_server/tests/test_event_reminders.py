import unittest
from datetime import datetime, timedelta
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from db.models import Base, User, Event, EventRegistration, Notification, EventReminderDelivery
from notifications.reminders import create_due_reminders


class EventReminderTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine('sqlite://')
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine, autoflush=False)()
        self.now = datetime(2026, 9, 15, 12)
        self.user = User(username='test', email='test@example.com', hashed_pw='unused', role='user')
        self.event = Event(title='Race', location='Track', event_date=self.now + timedelta(days=7))
        self.db.add_all([self.user, self.event])
        self.db.flush()
        self.db.add(EventRegistration(user_id=self.user.id, event_id=self.event.id, status='confirmed'))
        self.db.commit()

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def deliver(self, now=None):
        create_due_reminders(self.db, now=now or self.now)
        self.db.commit()

    def test_boundary_refresh_and_deletion(self):
        self.deliver(self.now - timedelta(seconds=1))
        self.assertEqual(self.db.query(Notification).count(), 0)
        self.deliver()
        first = self.db.query(Notification).one()
        first.is_read = True
        self.db.commit()
        self.deliver(self.now + timedelta(days=1))
        self.assertEqual(self.db.query(Notification).count(), 1)
        self.assertEqual(first.created_at, self.now)
        self.assertTrue(first.is_read)
        self.db.query(Notification).delete()
        self.db.commit()
        self.deliver()
        self.assertEqual(self.db.query(Notification).count(), 0)
        self.assertEqual(self.db.query(EventReminderDelivery).count(), 1)

    def test_registration_inside_window_before_confirmation(self):
        self.event.event_date = self.now + timedelta(days=2)
        self.db.query(EventRegistration).one().status = 'pending_payment'
        self.deliver()
        self.assertEqual(self.db.query(Notification).count(), 1)
        self.db.query(EventRegistration).one().status = 'confirmed'
        self.deliver()
        self.assertEqual(self.db.query(Notification).count(), 1)

    def test_excluded_waitlist_started_and_past_events(self):
        reg = self.db.query(EventRegistration).one()
        reg.status = 'waitlist'
        self.deliver()
        self.assertEqual(self.db.query(Notification).count(), 0)
        reg.status = 'confirmed'
        self.event.status = 'started'
        self.deliver()
        self.assertEqual(self.db.query(Notification).count(), 0)
        self.event.status = 'scheduled'
        self.event.event_date = self.now
        self.deliver()
        self.assertEqual(self.db.query(Notification).count(), 0)

    def test_rollback_does_not_consume_reminder(self):
        create_due_reminders(self.db, now=self.now)
        self.db.rollback()
        self.deliver()
        self.assertEqual(self.db.query(Notification).count(), 1)
