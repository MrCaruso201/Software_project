"""HTTP/SQLite fixture: real dependencies, synthetic data, no application lifespan."""
import base64
import io
import json
from pathlib import Path
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from urllib.parse import urlsplit

from fastapi import FastAPI
from PIL import Image
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker

from auth.jwt import create_access_token
from auth.router import router as auth_router
from auth.admin_router import router as admin_router
from events.router import router as events_router
from live.router import router as live_router
from results.router import router as results_router
from db.database import get_db
from db.models import Base, User, Event, EventRegistration

async def request(app, method, path, *, body=None, token=None, raw=None, content_type='application/json'):
    url = urlsplit(path)
    data = raw if raw is not None else json.dumps(body or {}).encode()
    headers = [(b'content-type', content_type.encode())]
    if token:
        headers.append((b'authorization', f'Bearer {token}'.encode()))
    scope = {'type': 'http', 'asgi': {'version': '3.0'}, 'http_version': '1.1',
             'method': method, 'scheme': 'http', 'path': url.path, 'raw_path': url.path.encode(),
             'query_string': url.query.encode(), 'headers': headers,
             'server': ('test', 80), 'client': ('test', 1)}
    messages = []
    async def receive():
        return {'type': 'http.request', 'body': data, 'more_body': False}
    async def send(message):
        messages.append(message)
    await app(scope, receive, send)
    status = next(m['status'] for m in messages if m['type'] == 'http.response.start')
    response = b''.join(m.get('body', b'') for m in messages if m['type'] == 'http.response.body')
    return status, response

class BackendFixture(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.url = f'sqlite:///{Path(self.directory.name)/"test.db"}'
        self.engine = create_engine(self.url, connect_args={'check_same_thread': False})
        @event.listens_for(self.engine, 'connect')
        def foreign_keys(connection, _):
            connection.execute('PRAGMA foreign_keys=ON')
        Base.metadata.create_all(self.engine)
        self.factory = sessionmaker(bind=self.engine, autoflush=False)
        self.db = self.factory()
        self.addCleanup(self.engine.dispose)
        self.addCleanup(self.db.close)
        self.users = {}
        self.tokens = {}
        for role in ['user', 'race_director', 'admin', 'viewer']:
            user = User(username=role, email=f'{role}@example.invalid', role=role, hashed_pw='unused')
            self.db.add(user)
            self.db.flush()
            self.users[role] = user
            self.tokens[role] = create_access_token(user.id, role)
        self.event = Event(title='Synthetic Race', location='Fixture Track',
                           event_date=datetime.now(timezone.utc).replace(tzinfo=None)+timedelta(days=10),
                           release_form_text='Synthetic waiver for automated testing.')
        self.db.add(self.event)
        self.db.flush()
        self.db.add(EventRegistration(user_id=self.users['user'].id, event_id=self.event.id, status='pending_payment'))
        self.db.commit()
        self.app = FastAPI()
        for router in [auth_router, admin_router, results_router, events_router, live_router]:
            self.app.include_router(router)
        def database():
            with self.factory() as session:
                yield session
        self.app.dependency_overrides[get_db] = database
        image = io.BytesIO()
        Image.new('RGB', (2, 2), 'black').save(image, format='PNG')
        self.waiver = {'first_name':'Synthetic', 'last_name':'Driver', 'codice_fiscale':'TEST',
                       'birth_date':'2000-01-01', 'residence':'Test City',
                       'signature_base64':base64.b64encode(image.getvalue()).decode()}

    async def http(self, method, path, role='user', **kwargs):
        return await request(self.app, method, path, token=self.tokens.get(role), **kwargs)

    async def sign(self):
        status, data = await self.http('POST', f'/events/{self.event.id}/release-form/sign', body=self.waiver)
        self.assertEqual(status, 200, data)

    async def import_csv(self, role='admin', text='Posizione,Pilota\n1,Synthetic\n'):
        boundary = 'fixture-boundary'
        raw = (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="results.csv"\r\n'
               f'Content-Type: text/csv\r\n\r\n{text}\r\n--{boundary}--\r\n').encode()
        return await self.http('POST', f'/events/{self.event.id}/results/import_csv', role,
                               raw=raw, content_type=f'multipart/form-data; boundary={boundary}')
