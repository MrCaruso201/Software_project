import unittest
from datetime import datetime
from unittest.mock import patch

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from db.models import Base, User, Event, EventRegistration
from events.router import register_for_event, update_team_registration, update_event
from events.schemas import TeamRegistrationRequest, EventUpdate


class EventRegistrationIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine('sqlite://')
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine, autoflush=False)()
        self.users = [User(username=f'u{i}', email=f'u{i}@test.local', hashed_pw='unused') for i in range(3)]
        self.event = Event(title='Test', location='Track', event_date=datetime(2026,10,20),
                           days_before_deadline=3, registration_deadline=datetime(2026,10,17),
                           min_people_per_group=2, max_people_per_group=None)
        self.db.add_all([*self.users, self.event]); self.db.commit()
        self.payload = {'sub': str(self.users[0].id), 'role': 'user'}
        self.notifications = patch('events.router.notify_user'); self.notifications.start()

    def tearDown(self):
        self.notifications.stop(); self.db.close(); self.engine.dispose()

    def create_team(self):
        return register_for_event(self.event.id, TeamRegistrationRequest(team_name='Team', member_emails=[self.users[1].email]), self.payload, self.db)

    def test_optional_max_and_rename_preserve_member_attributes(self):
        leader = self.create_team()
        member = self.db.query(EventRegistration).filter_by(user_id=self.users[1].id).one()
        member.weight = 75; self.db.commit()
        old_id = member.id
        update_team_registration(self.event.id, leader.team_id,
            TeamRegistrationRequest(team_name='Renamed', member_emails=['@u1'], accepts_extra_pilots=True), self.payload, self.db)
        member = self.db.query(EventRegistration).filter_by(user_id=self.users[1].id).one()
        self.assertEqual((member.id, member.weight, member.team_name), (old_id, 75, 'Renamed'))
        self.assertTrue(member.accepts_extra_pilots)

    def test_member_replacement(self):
        leader = self.create_team()
        update_team_registration(self.event.id, leader.team_id,
            TeamRegistrationRequest(team_name='Team', member_emails=[self.users[2].email]), self.payload, self.db)
        self.assertEqual({r.user_id for r in self.db.query(EventRegistration).all()}, {self.users[0].id, self.users[2].id})

    def test_duplicates_rejected_before_insert(self):
        for members in ([self.users[0].email], ['@u1', self.users[1].email], ['guest@test.local', 'GUEST@test.local']):
            with self.subTest(members=members), self.assertRaises(HTTPException) as error:
                register_for_event(self.event.id, TeamRegistrationRequest(team_name='Team', member_emails=members), self.payload, self.db)
            self.assertEqual(error.exception.status_code, 400)
            self.assertEqual(self.db.query(EventRegistration).count(), 0)

    def test_duplicate_edit_preserves_team(self):
        leader = self.create_team()
        with self.assertRaises(HTTPException):
            update_team_registration(self.event.id, leader.team_id, TeamRegistrationRequest(team_name='Bad', member_emails=['@u0']), self.payload, self.db)
        self.db.commit()
        self.assertEqual(leader.team_name, 'Team')
        self.assertEqual(self.db.query(EventRegistration).count(), 2)

    def test_explicit_max_is_enforced(self):
        self.event.max_people_per_group = 2; self.db.commit()
        with self.assertRaises(HTTPException):
            register_for_event(self.event.id, TeamRegistrationRequest(team_name='Team', member_emails=['@u1', '@u2']), self.payload, self.db)

    def test_deadline_follows_date_and_respects_explicit_override(self):
        update_event(self.event.id, EventUpdate(event_date=datetime(2026,10,30)), self.db)
        self.assertEqual(self.event.registration_deadline, datetime(2026,10,27))
        update_event(self.event.id, EventUpdate(event_date=datetime(2026,11,1), registration_deadline=datetime(2026,10,25)), self.db)
        self.assertEqual(self.event.registration_deadline, datetime(2026,10,25))
        update_event(self.event.id, EventUpdate(days_before_deadline=None), self.db)
        self.assertIsNone(self.event.registration_deadline)

    def test_generic_status_patch_rejected_without_changes(self):
        for status in ('started', 'invalid', None):
            with self.assertRaises(HTTPException) as error:
                update_event(self.event.id, EventUpdate(status=status, title='Changed'), self.db)
            self.assertEqual(error.exception.status_code, 400)
            self.assertEqual(self.event.status, 'scheduled')
            self.assertEqual(self.event.title, 'Test')
