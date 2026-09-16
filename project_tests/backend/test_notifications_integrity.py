"""Exercise real notification persistence in an isolated database (no mocked sender)."""
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from fastapi import BackgroundTasks, HTTPException
from sqlalchemy import create_engine, event as sqlalchemy_event
from sqlalchemy.orm import sessionmaker

from db.models import Base, User, Event, EventRegistration, Notification
from events.router import (create_event, admin_register_team, confirm_registration,
                           move_to_waitlist_registration, accept_waitlist_registration)
from events.schemas import EventCreate, AdminTeamRegistrationRequest
from notifications.router import (get_my_notifications, mark_notification_read,
                                  delete_single_notification, delete_all_notifications,
                                  notify_user, _is_event_past)


class NotificationIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine('sqlite://')
        @sqlalchemy_event.listens_for(self.engine, 'connect')
        def enable_foreign_keys(connection, _):
            connection.execute('PRAGMA foreign_keys=ON')
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine, autoflush=False)()
        self.users = [User(username=f'u{i}', email=f'u{i}@test.local', hashed_pw='unused', role=role)
                      for i, role in enumerate(['user', 'user', 'race_director', 'admin', 'viewer'])]
        self.db.add_all(self.users)
        self.db.commit()
        self.payload = {'sub': str(self.users[3].id), 'role': 'admin'}

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def create_event(self):
        return create_event(EventCreate(title='Race', location='Track',
                            event_date=datetime.now() + timedelta(days=10)), self.db)

    def test_new_event_persists_one_notification_per_eligible_account(self):
        event = self.create_event()
        expected_users = {u.id for u in self.users[:4]}
        self.db.close()  # Verify committed rows, rather than pending ORM objects.
        rows = self.db.query(Notification).filter_by(event_id=event.id, type='new_event').all()
        self.assertEqual({n.user_id for n in rows}, expected_users)
        self.assertEqual(len(rows), 4)
        self.assertTrue(all(not n.is_read for n in rows))

    def test_event_and_notifications_rollback_together_on_failure(self):
        with patch('events.router.notify_user', side_effect=RuntimeError('failed')):
            with self.assertRaises(RuntimeError):
                self.create_event()
        self.db.rollback()
        self.assertEqual(self.db.query(Event).count(), 0)
        self.assertEqual(self.db.query(Notification).count(), 0)

    def test_team_actions_notify_all_linked_members(self):
        event = self.create_event()
        leader = admin_register_team(event.id, AdminTeamRegistrationRequest(
            team_name='Team', leader_email=self.users[0].email,
            member_emails=[self.users[1].email, 'no-account@test.local']), self.payload, self.db)
        for action, kind in [(None, 'admin_registered'),
                             (move_to_waitlist_registration, 'moved_to_waitlist'),
                             (accept_waitlist_registration, 'registration_accepted'),
                             (confirm_registration, 'registration_confirmed')]:
            if action:
                action(event.id, leader.id, self.payload, self.db)
            self.db.expire_all()
            rows = self.db.query(Notification).filter_by(event_id=event.id, type=kind).all()
            self.assertEqual({n.user_id for n in rows}, {self.users[0].id, self.users[1].id})
            self.assertEqual(len(rows), 2)
        self.assertTrue(all(r.status == 'confirmed' for r in self.db.query(EventRegistration).all()))

    def test_inbox_ownership_read_and_delete(self):
        self.create_event()
        payload = {'sub': str(self.users[0].id)}
        own = get_my_notifications(self.db, payload)
        self.assertEqual(len(own), 1)
        other = self.db.query(Notification).filter_by(user_id=self.users[1].id).one()
        for operation in [mark_notification_read, delete_single_notification]:
            with self.assertRaises(HTTPException) as error:
                operation(other.id, self.db, payload)
            self.assertEqual(error.exception.status_code, 404)
        mark_notification_read(own[0].id, self.db, payload)
        self.db.expire_all()
        self.assertTrue(get_my_notifications(self.db, payload)[0].is_read)
        delete_single_notification(own[0].id, self.db, payload)
        self.assertEqual(get_my_notifications(self.db, payload), [])
        delete_all_notifications({'sub': str(self.users[1].id)}, self.db)
        self.assertEqual(self.db.query(Notification).count(), 2)

    def test_expiry_accepts_database_dates_and_preserves_recent_notifications(self):
        event = self.create_event()
        event.event_date = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(hours=25)
        self.db.commit()
        self.assertEqual(get_my_notifications(self.db, {'sub': str(self.users[0].id)}), [])
        self.assertEqual(self.db.query(Notification).count(), 3)
        self.assertFalse(_is_event_past(datetime.now(timezone.utc) - timedelta(hours=23)))
        self.assertTrue(_is_event_past(event.event_date.isoformat()))

    def test_sender_without_linked_account_does_not_create_notification(self):
        event = self.create_event()
        notify_user(self.db, None, event.id, 'test', 'Test', 'Test')
        self.assertEqual(self.db.query(Notification).count(), 4)

    def test_start_event_notifies_confirmed_and_removes_unconfirmed(self):
        from live.router import update_event_status
        from live.schemas import EventStatusUpdate
        event = self.create_event()
        self.db.add_all([
            EventRegistration(event_id=event.id, user_id=self.users[0].id, status='confirmed'),
            EventRegistration(event_id=event.id, user_id=self.users[1].id, status='pending_payment'),
        ])
        self.db.commit()
        update_event_status(event.id, EventStatusUpdate(status='started'), BackgroundTasks(), self.payload, self.db)
        self.db.expire_all()
        self.assertEqual(self.db.query(Notification).filter_by(type='event_started').one().user_id, self.users[0].id)
        self.assertEqual(self.db.query(Notification).filter_by(type='registration_deleted').one().user_id, self.users[1].id)
        self.assertEqual(self.db.query(EventRegistration).count(), 1)
        update_event_status(event.id, EventStatusUpdate(status='started'), BackgroundTasks(), self.payload, self.db)
        self.assertEqual(self.db.query(Notification).filter_by(type='event_started').count(), 1)
