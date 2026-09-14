import unittest
from datetime import datetime, timedelta

from fastapi import BackgroundTasks, HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from db.models import Base, Event, LiveKartAssignment, RaceMessage, RacePenalty
from live.router import send_message
from live.schemas import MessageCreate


class MessageScopeTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine('sqlite://')
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine)()
        self.event = Event(title='Test', event_date=datetime.now(), location='Track', race_status='running')
        self.db.add(self.event)
        self.db.flush()
        self.kart = LiveKartAssignment(event_id=self.event.id, team_id='team', kart_number=7,
                                      stint_elapsed_seconds=12, stint_last_resume=datetime.now() - timedelta(seconds=10))
        self.db.add(self.kart)
        self.db.commit()

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def send(self, kind, text, target):
        tasks = BackgroundTasks()
        message = send_message(self.event.id, MessageCreate(message_type=kind, text=text, target_kart=target),
                               tasks, {'role': 'race_director'}, self.db, None)
        return message, tasks

    def test_targeted_control_commands_are_rejected_without_side_effects(self):
        before = (self.kart.stint_elapsed_seconds, self.kart.stint_last_resume)
        for kind, text in [('red_flag', 'Rossa'), ('green_flag', 'Verde'), ('checkered_flag', 'Fine'),
                           ('custom', ' Gara Iniziata '), ('custom', ' TURNO INIZIATO ')]:
            for target in (7, 0):
                with self.subTest(kind=kind, target=target), self.assertRaises(HTTPException) as caught:
                    self.send(kind, text, target)
                self.assertEqual(caught.exception.status_code, 400)
                self.db.commit()
                self.assertEqual(self.event.race_status, 'running')
                self.assertEqual((self.kart.stint_elapsed_seconds, self.kart.stint_last_resume), before)
                self.assertEqual(self.db.query(RaceMessage).count(), 0)
                self.assertEqual(self.db.query(RacePenalty).count(), 0)

    def test_targeted_information_remains_supported(self):
        before = (self.kart.stint_elapsed_seconds, self.kart.stint_last_resume)
        message, _ = self.send('custom', 'Rientra ai box', 7)
        self.assertEqual(message.target_kart, 7)
        self.assertEqual(self.event.race_status, 'running')
        self.assertEqual((self.kart.stint_elapsed_seconds, self.kart.stint_last_resume), before)

    def test_broadcast_controls_keep_timer_transitions(self):
        self.send('red_flag', 'Rossa', None)
        self.assertEqual(self.event.race_status, 'paused')
        self.assertIsNone(self.kart.stint_last_resume)
        elapsed = self.kart.stint_elapsed_seconds
        self.send('green_flag', 'Verde', None)
        self.assertEqual(self.event.race_status, 'running')
        self.assertEqual(self.kart.stint_elapsed_seconds, elapsed)
        self.assertIsNotNone(self.kart.stint_last_resume)
        self.send('checkered_flag', 'Fine', None)
        self.assertEqual(self.event.race_status, 'stopped')
        self.assertIsNone(self.kart.stint_last_resume)
        self.send('custom', ' Turno Iniziato ', None)
        self.assertEqual(self.event.race_status, 'running')
        self.assertEqual(self.kart.stint_elapsed_seconds, 0)
        self.assertIsNotNone(self.kart.stint_last_resume)
