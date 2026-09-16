import asyncio
import json
import unittest
from unittest.mock import AsyncMock, Mock, patch

from fastapi import WebSocketDisconnect
from ws import manager
from ws.router import websocket_endpoint


class WebSocketInputTests(unittest.IsolatedAsyncioTestCase):
    async def exercise(self, incoming, send_error=None):
        ws = Mock()
        ws.accept = AsyncMock()
        ws.receive_text = AsyncMock(side_effect=incoming)
        ws.send_text = AsyncMock(side_effect=send_error)
        session = Mock()
        with patch('ws.router.verify_websocket_token', AsyncMock(return_value={'role': 'user'})), \
             patch.object(manager, 'client_url', {ws: 'https://test'}), \
             patch.object(manager, 'client_event', {ws: 7}), \
             patch.object(manager, 'sessions', {'https://test': session}):
            try:
                await websocket_endpoint(ws)
            finally:
                self.assertNotIn(ws, manager.client_url)
                self.assertNotIn(ws, manager.client_event)
                session.remove_subscriber.assert_called_once()
        return [json.loads(call.args[0]) for call in ws.send_text.await_args_list]

    async def test_malformed_messages_allow_next_valid_command(self):
        invalid = ['{', '[]', 'null', '42', '{}', '{"command": []}',
                   '{"command":"set_url","url":null}', '{"command":"set_url","url":12}',
                   '{"command":"subscribe_event","event_id":true}',
                   '{"command":"subscribe_event","event_id":-1}', '{"command":"unknown"}']
        for raw in invalid:
            with self.subTest(raw=raw):
                responses = await self.exercise([raw, '{"command":"get_status"}', WebSocketDisconnect()])
                self.assertEqual([r['type'] for r in responses], ['error', 'status'])

    async def test_unexpected_receive_error_releases_subscriptions(self):
        with self.assertRaises(RuntimeError):
            await self.exercise([RuntimeError('receive failed')])

    async def test_error_response_send_failure_releases_subscriptions(self):
        with self.assertRaises(RuntimeError):
            await self.exercise(['{'], RuntimeError('send failed'))

    async def test_cancellation_releases_subscriptions(self):
        with self.assertRaises(asyncio.CancelledError):
            await self.exercise([asyncio.CancelledError()])
