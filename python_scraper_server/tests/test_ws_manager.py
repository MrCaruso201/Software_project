import unittest
from unittest.mock import AsyncMock, Mock, patch

from ws import manager
from scraper.session import ScraperSession


class BroadcastCleanupTests(unittest.IsolatedAsyncioTestCase):
    async def test_failed_broadcast_releases_last_subscriber_once(self):
        for broadcast, target in ((manager.broadcast_to_url, 'https://test'),
                                  (manager.broadcast_to_event, 7)):
            with self.subTest(broadcast=broadcast.__name__):
                ws = Mock()
                ws.send_text = AsyncMock(side_effect=RuntimeError('Disconnected'))
                session = Mock(spec=ScraperSession)
                session.subscriber_count = 1
                session.remove_subscriber.side_effect = lambda: ScraperSession.remove_subscriber(session)
                with patch.object(manager, 'client_url', {ws: 'https://test'}), \
                     patch.object(manager, 'client_event', {ws: 7}), \
                     patch.object(manager, 'sessions', {'https://test': session}):
                    await broadcast(target, {'type': 'test'})
                    manager.unsubscribe_client(ws)
                    self.assertEqual(session.subscriber_count, 0)
                    session.remove_subscriber.assert_called_once()
                    session._schedule_stop.assert_called_once()
                    self.assertNotIn(ws, manager.client_url)
                    self.assertNotIn(ws, manager.client_event)

    async def test_failure_preserves_other_subscribers_and_delivery(self):
        for broadcast, target in ((manager.broadcast_to_url, 'https://test'),
                                  (manager.broadcast_to_event, 7)):
            with self.subTest(broadcast=broadcast.__name__):
                failed, healthy = Mock(), Mock()
                failed.send_text = AsyncMock(side_effect=RuntimeError('Disconnected'))
                healthy.send_text = AsyncMock()
                session = Mock(spec=ScraperSession)
                session.subscriber_count = 2
                session.remove_subscriber.side_effect = lambda: ScraperSession.remove_subscriber(session)
                with patch.object(manager, 'client_url', {failed: 'https://test', healthy: 'https://test'}), \
                     patch.object(manager, 'client_event', {failed: 7, healthy: 7}), \
                     patch.object(manager, 'sessions', {'https://test': session}):
                    await broadcast(target, {'type': 'test'})
                    self.assertEqual(session.subscriber_count, 1)
                    session._schedule_stop.assert_not_called()
                    healthy.send_text.assert_awaited_once()
                    self.assertIn(healthy, manager.client_url)
                    self.assertIn(healthy, manager.client_event)

    async def test_event_only_client_failure_needs_no_scraper(self):
        ws = Mock()
        ws.send_text = AsyncMock(side_effect=RuntimeError('Disconnected'))
        with patch.object(manager, 'client_url', {}), \
             patch.object(manager, 'client_event', {ws: 7}), \
             patch.object(manager, 'sessions', {}):
            await manager.broadcast_to_event(7, {'type': 'test'})
            manager.unsubscribe_client(ws)
            self.assertEqual(manager.client_event, {})
