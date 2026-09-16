"""Role changes invalidate access tokens until renewed; deletion denies renewal."""
import json
from unittest.mock import AsyncMock, patch

from acceptance_support import BackendFixture, request
from auth.jwt import create_access_token
from auth.password import hash_password
from auth.token import verify_websocket_token


class TokenRenewalTests(BackendFixture):
    async def login_user(self):
        self.users['user'].hashed_pw = hash_password('fixture-password')
        self.db.commit()
        status, data = await self.http('POST', '/auth/login', role=None,
                                      body={'username':'user', 'password':'fixture-password'})
        self.assertEqual(status, 200, data)
        return json.loads(data)

    async def change_role(self, role):
        status, data = await self.http('PATCH', f'/admin/users/{self.users["user"].id}/role',
                                      'admin', body={'role':role})
        self.assertEqual(status, 200, data)
        self.db.expire_all()

    async def test_role_change_requires_refresh_and_old_token_never_revives(self):
        tokens = await self.login_user()
        original = tokens['access_token']
        await self.change_role('race_director')
        self.assertEqual(self.users['user'].token_version, 1)
        status, _ = await request(self.app, 'GET', '/auth/me', token=original)
        self.assertEqual(status, 401)
        ws = AsyncMock()
        ws.query_params = {'token':original}
        with patch('auth.token.SessionLocal', self.factory):
            self.assertIsNone(await verify_websocket_token(ws))
        ws.close.assert_awaited_once_with(code=4401)
        status, data = await self.http('POST', '/auth/refresh', role=None,
                                      body={'refresh_token':tokens['refresh_token']})
        self.assertEqual(status, 200, data)
        renewed = json.loads(data)['access_token']
        status, data = await request(self.app, 'GET', '/auth/me', token=renewed)
        self.assertEqual(status, 200, data)
        self.assertEqual(json.loads(data)['role'], 'race_director')
        await self.change_role('user')
        self.assertEqual(self.users['user'].token_version, 2)
        for old in [original, renewed]:
            status, _ = await request(self.app, 'GET', '/auth/me', token=old)
            self.assertEqual(status, 401)
        status, data = await self.http('POST', '/auth/refresh', role=None,
                                      body={'refresh_token':tokens['refresh_token']})
        self.assertEqual(status, 200, data)
        status, data = await request(self.app, 'GET', '/auth/me', token=json.loads(data)['access_token'])
        self.assertEqual(status, 200, data)
        self.assertEqual(json.loads(data)['role'], 'user')

    async def test_unchanged_role_does_not_revoke_access(self):
        token = self.tokens['user']
        await self.change_role('user')
        self.assertEqual(self.users['user'].token_version, 0)
        status, _ = await request(self.app, 'GET', '/auth/me', token=token)
        self.assertEqual(status, 200)

    async def test_deleted_account_cannot_refresh(self):
        tokens = await self.login_user()
        status, _ = await request(self.app, 'DELETE', '/auth/me', token=tokens['access_token'])
        self.assertEqual(status, 204)
        status, _ = await request(self.app, 'GET', '/auth/me', token=tokens['access_token'])
        self.assertEqual(status, 401)
        status, _ = await self.http('POST', '/auth/refresh', role=None,
                                    body={'refresh_token':tokens['refresh_token']})
        self.assertEqual(status, 401)

    async def test_legacy_database_gets_token_version_without_losing_accounts(self):
        from sqlalchemy import create_engine, text
        from db import database
        engine = create_engine('sqlite://')
        try:
            with engine.begin() as connection:
                connection.execute(text('CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT)'))
                connection.execute(text("INSERT INTO users VALUES (1, 'legacy')"))
            with patch.object(database, 'engine', engine), \
                 patch.object(database, '_migrate_event_registrations_nullable_userid'):
                database._apply_migrations()
                database._apply_migrations()
            with engine.connect() as connection:
                row = connection.execute(text('SELECT username, token_version FROM users WHERE id=1')).one()
            self.assertEqual(tuple(row), ('legacy', 0))
        finally:
            engine.dispose()
