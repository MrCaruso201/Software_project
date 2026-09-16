import asyncio
import io
import json
import unittest
from datetime import datetime
from unittest.mock import AsyncMock, patch

from fastapi import FastAPI, HTTPException, UploadFile
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from auth.jwt import create_access_token
from auth.token import verify_websocket_token
from db.database import get_db
from db.models import Base, User, Event, EventResult
from events.router import router
from results.router import import_results_from_csv


class AccessIntegrityTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
        Base.metadata.create_all(self.engine)
        self.factory = sessionmaker(bind=self.engine, autoflush=False)
        self.db = self.factory()
        self.user = User(username='test', email='test@example.com', hashed_pw='unused', role='admin')
        self.event = Event(title='Original', event_date=datetime(2026, 9, 14), location='Track')
        self.db.add_all([self.user, self.event])
        self.db.commit()
        self.token = create_access_token(self.user.id, 'admin')
        self.app = FastAPI()
        self.app.include_router(router)
        def database():
            with self.factory() as db:
                yield db
        self.app.dependency_overrides[get_db] = database

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    async def request(self, method, path, body=None, token=None):
        payload = json.dumps(body or {}).encode()
        headers = [(b'content-type', b'application/json')]
        if token:
            headers.append((b'authorization', f'Bearer {token}'.encode()))
        scope = {'type': 'http', 'asgi': {'version': '3.0'}, 'http_version': '1.1',
                 'method': method, 'scheme': 'http', 'path': path, 'raw_path': path.encode(),
                 'query_string': b'', 'headers': headers, 'server': ('test', 80), 'client': ('test', 1)}
        messages = []
        async def receive():
            return {'type': 'http.request', 'body': payload, 'more_body': False}
        async def send(message):
            messages.append(message)
        await self.app(scope, receive, send)
        return next(m['status'] for m in messages if m['type'] == 'http.response.start')

    async def test_event_writes_require_current_director_role(self):
        for role, expected in [('viewer', 403), ('user', 403), ('race_director', 200), ('admin', 200)]:
            self.user.role = role
            self.db.commit()
            self.assertEqual(await self.request('PATCH', f'/events/{self.event.id}', {'title': role}, self.token), expected)
        for method, path, body in [('POST', '/events/', {'title': 'New', 'event_date': '2026-09-14T12:00:00', 'location': 'Track'}),
                                   ('PATCH', f'/events/{self.event.id}', {'title': 'Changed'}),
                                   ('DELETE', f'/events/{self.event.id}', {})]:
            self.assertEqual(await self.request(method, path, body), 401)
            self.user.role = 'viewer'
            self.db.commit()
            self.assertEqual(await self.request(method, path, body, self.token), 403)
        self.user.role = 'race_director'
        self.db.commit()
        self.assertEqual(await self.request('POST', '/events/', {'title': 'New', 'event_date': '2026-09-14T12:00:00', 'location': 'Track'}, self.token), 201)
        self.assertEqual(await self.request('DELETE', f'/events/{self.event.id}', token=self.token), 204)

    async def test_deleted_account_token_is_rejected(self):
        self.db.delete(self.user)
        self.db.commit()
        self.assertEqual(await self.request('PATCH', f'/events/{self.event.id}', {'title': 'Changed'}, self.token), 401)

    async def test_websocket_uses_current_account(self):
        ws = AsyncMock()
        ws.query_params = {'token': self.token}
        with patch('auth.token.SessionLocal', self.factory):
            self.user.role = 'viewer'
            self.db.commit()
            self.assertEqual((await verify_websocket_token(ws))['role'], 'viewer')
            self.db.delete(self.user)
            self.db.commit()
            self.assertIsNone(await verify_websocket_token(ws))
            ws.close.assert_awaited_once_with(code=4401)

    async def test_idle_websocket_revalidates_and_unsubscribes(self):
        from ws.router import websocket_endpoint
        ws = AsyncMock()
        calls = 0
        async def receive():
            nonlocal calls
            calls += 1
            raise asyncio.TimeoutError()
        ws.receive_text.side_effect = receive
        with patch('ws.router.verify_websocket_token', AsyncMock(side_effect=[{'role': 'user'}, None])) as verify, patch('ws.router.unsubscribe_client') as unsubscribe:
            await websocket_endpoint(ws)
            self.assertEqual(verify.await_count, 2)
            self.assertEqual(calls, 1)
            unsubscribe.assert_called_once_with(ws)

    async def test_invalid_csv_preserves_previous_results(self):
        self.db.add(EventResult(event_id=self.event.id, position=1, driver_name='Original', is_official=True))
        self.db.commit()
        for content in (b'', b'Posizione,Pilota\n', b'Posizione,Pilota\ninvalid,Test\n'):
            with self.assertRaises(HTTPException) as caught:
                await import_results_from_csv(self.event.id, 'final', UploadFile(file=io.BytesIO(content)), {'role': 'admin'}, self.db)
            self.assertEqual(caught.exception.status_code, 400)
            self.assertEqual(self.db.query(EventResult).one().driver_name, 'Original')

    async def test_partial_csv_replaces_results_and_reports_errors(self):
        self.db.add(EventResult(event_id=self.event.id, position=1, driver_name='Original', is_official=True))
        self.db.commit()
        result = await import_results_from_csv(self.event.id, 'final', UploadFile(file=io.BytesIO(b'Posizione,Pilota\ninvalid,Skipped\n1,New\n')), {'role': 'admin'}, self.db)
        self.assertEqual(result.imported, 1)
        self.assertTrue(result.errors)
        self.assertEqual(self.db.query(EventResult).one().driver_name, 'New')
