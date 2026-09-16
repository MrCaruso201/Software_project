import unittest
from datetime import datetime
from unittest.mock import AsyncMock, Mock, patch

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from db.models import Base, Event, Kartodromo
from kartodromi.router import update_kartodromo
from kartodromi.schemas import KartodromoUpdate
from ws import manager


class KartodromoUpdateTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine)()
        self.track = Kartodromo(nome='Track', luogo='City', url='https://track.test')
        self.other = Kartodromo(nome='Other', url='https://other.test')
        self.db.add_all([self.track, self.other])
        self.db.commit()

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def event(self, location, status, race_status='running'):
        self.db.add(Event(title='Race', event_date=datetime(2026, 9, 15),
                          location=location, status=status, race_status=race_status))
        self.db.commit()

    async def test_live_event_blocks_without_disconnect_or_changes(self):
        for location in ['Track', 'Track - City']:
            for race_status in ['running', 'paused', 'not_started', 'stopped']:
                with self.subTest(location=location, race_status=race_status):
                    self.event(location, 'started', race_status)
                    with patch('kartodromi.router.disconnect_clients_for_url', new_callable=AsyncMock) as disconnect:
                        with self.assertRaises(HTTPException) as error:
                            await update_kartodromo(self.track.id, KartodromoUpdate(nome='Changed'), self.db, {})
                        self.assertEqual(error.exception.status_code, 409)
                        disconnect.assert_not_awaited()
                        self.db.rollback()
                        self.assertEqual(self.track.nome, 'Track')
                    self.db.query(Event).delete()
                    self.db.commit()

    async def test_disconnect_precedes_save_and_only_affects_target(self):
        self.event('Track', 'finished')
        self.event('Track', 'scheduled')
        self.event('Other', 'started')
        target, other = Mock(), Mock()
        old_url = self.track.url

        async def close(**kwargs):
            self.assertEqual(self.track.nome, 'Track')
            self.assertEqual(self.track.url, old_url)
            self.assertIn(old_url, manager.updating_urls)
            self.assertNotIn(target, manager.client_url)
        target.close = AsyncMock(side_effect=close)
        other.close = AsyncMock()
        session = Mock()
        with patch.object(manager, 'client_url', {target: old_url, other: self.other.url}), \
             patch.object(manager, 'client_event', {target: 1, other: 2}), \
             patch.object(manager, 'sessions', {old_url: session}):
            updated = await update_kartodromo(self.track.id, KartodromoUpdate(nome='Changed', url='https://new.test'), self.db, {})
            self.assertEqual(updated.nome, 'Changed')
            self.assertEqual(updated.url, 'https://new.test')
            target.close.assert_awaited_once()
            other.close.assert_not_awaited()
            session.remove_subscriber.assert_called_once()
            self.assertEqual(manager.client_event, {other: 2})
        self.assertNotIn(old_url, manager.updating_urls)

    async def test_duplicate_url_does_not_disconnect(self):
        with patch('kartodromi.router.disconnect_clients_for_url', new_callable=AsyncMock) as disconnect:
            with self.assertRaises(HTTPException) as error:
                await update_kartodromo(self.track.id, KartodromoUpdate(url=self.other.url), self.db, {})
            self.assertEqual(error.exception.status_code, 409)
            disconnect.assert_not_awaited()

    async def test_timeout_aborts_save_and_unblocks_url(self):
        old_url = self.track.url
        with patch('kartodromi.router.disconnect_clients_for_url', new_callable=AsyncMock, side_effect=TimeoutError):
            with self.assertRaises(HTTPException) as error:
                await update_kartodromo(self.track.id, KartodromoUpdate(nome='Changed'), self.db, {})
            self.assertEqual(error.exception.status_code, 503)
        self.assertEqual(self.track.nome, 'Track')
        self.assertNotIn(old_url, manager.updating_urls)

    async def test_save_without_connected_clients(self):
        with patch.object(manager, 'client_url', {}):
            updated = await update_kartodromo(self.track.id, KartodromoUpdate(sito_web='https://website.test'), self.db, {})
        self.assertEqual(updated.sito_web, 'https://website.test')
