"""Additional DD/RASD acceptance checks. Failures remain visible, never expectedFailure."""
import asyncio
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import AsyncMock, Mock, patch

from fastapi import FastAPI
from jose import jwt
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from acceptance_support import BackendFixture, request
from auth.jwt import SECRET_KEY, ALGORITHM
from db.models import User, EventRegistration, SignedRelease, EventResult
from ws import manager

class DocumentAcceptanceTests(BackendFixture):
    async def test_T1_register_login_refresh_logout(self):
        details = {'username':'new-driver', 'email':'new@example.invalid', 'password':'test-password'}
        status, data = await self.http('POST', '/auth/register', role=None, body=details)
        self.assertEqual(status, 201, data)
        saved = self.db.query(User).filter_by(username='new-driver').one()
        self.assertEqual(saved.role, 'user')
        self.assertNotEqual(saved.hashed_pw, details['password'])
        status, data = await self.http('POST', '/auth/login', role=None,
                                       body={'username':'new-driver', 'password':'wrong'})
        self.assertEqual(status, 401)
        status, data = await self.http('POST', '/auth/login', role=None,
                                       body={'username':'new-driver', 'password':'test-password'})
        self.assertEqual(status, 200, data)
        tokens = json.loads(data)
        for path, expected in [('/auth/refresh', 200), ('/auth/logout', 200), ('/auth/refresh', 401)]:
            status, data = await self.http('POST', path, role=None, body={'refresh_token':tokens['refresh_token']})
            self.assertEqual(status, expected, data)

    async def test_T1_duplicate_identity_rejected(self):
        for name, email in [('user', 'different@example.invalid'), ('different', 'user@example.invalid')]:
            status, _ = await self.http('POST', '/auth/register', role=None,
                                       body={'username':name, 'email':email, 'password':'test'})
            self.assertEqual(status, 400)
        self.assertEqual(self.db.query(User).count(), 4)

    async def test_T1_profile_cannot_promote_self(self):
        status, data = await self.http('PATCH', '/auth/me', body={'first_name':'Updated', 'role':'admin'})
        self.assertEqual(status, 200, data)
        self.assertEqual(json.loads(data)['role'], 'user')
        self.assertEqual(json.loads(data)['first_name'], 'Updated')

    async def test_T1_expired_token_rejected(self):
        expired = jwt.encode({'sub':str(self.users['user'].id), 'role':'user',
                              'exp':datetime.now(timezone.utc)-timedelta(seconds=1)}, SECRET_KEY, algorithm=ALGORITHM)
        status, _ = await request(self.app, 'GET', '/auth/me', token=expired)
        self.assertEqual(status, 401)

    async def test_A1_duplicate_registration(self):
        status, _ = await self.http('POST', f'/events/{self.event.id}/register', raw=b'null')
        self.assertEqual(status, 400)
        self.assertEqual(self.db.query(EventRegistration).count(), 1)

    async def test_A2_late_registration_enters_waitlist(self):
        self.db.query(EventRegistration).delete()
        self.event.registration_deadline = datetime.now(timezone.utc).replace(tzinfo=None)-timedelta(seconds=1)
        self.db.commit()
        status, data = await self.http('POST', f'/events/{self.event.id}/register', raw=b'null')
        self.assertEqual(status, 201, data)
        self.assertEqual(json.loads(data)['status'], 'waitlist')

    async def test_T2_confirmed_self_cancellation_blocked(self):
        self.db.query(EventRegistration).update({'status':'confirmed'})
        self.db.commit()
        status, _ = await self.http('DELETE', f'/events/{self.event.id}/register', raw=b'null')
        self.assertIn(status, (400, 403, 409))
        self.assertEqual(self.db.query(EventRegistration).count(), 1)

    async def test_A3_account_cannot_change_roles(self):
        status, _ = await self.http('PATCH', f'/admin/users/{self.users["user"].id}/role', body={'role':'admin'})
        self.assertEqual(status, 403)

    async def test_A4_source_and_event_isolation(self):
        a, b = Mock(), Mock()
        a.send_text, b.send_text = AsyncMock(), AsyncMock()
        with patch.object(manager, 'client_url', {a:'source-A', b:'source-B'}), \
             patch.object(manager, 'client_event', {a:1, b:2}):
            await manager.broadcast_to_url('source-A', {'type':'timing_update'})
            a.send_text.assert_awaited_once()
            b.send_text.assert_not_awaited()
            a.send_text.reset_mock()
            await manager.broadcast_to_event(2, {'type':'event_update'})
            b.send_text.assert_awaited_once()
            a.send_text.assert_not_awaited()

    async def test_A8_waiver_preview_store_pdf_remove(self):
        status, data = await self.http('POST', f'/events/{self.event.id}/release-form/preview', body=self.waiver)
        self.assertEqual(status, 200, data)
        self.assertTrue(data.startswith(b'%PDF-'))
        await self.sign()
        release = self.db.query(SignedRelease).one()
        self.assertEqual((release.event_id, release.user_id), (self.event.id, self.users['user'].id))
        status, data = await self.http('GET', f'/events/{self.event.id}/release-form/mine')
        self.assertEqual(status, 200, data)
        self.assertEqual(json.loads(data)['signature_base64'], self.waiver['signature_base64'])
        path = f'/admin/events/{self.event.id}/releases/{self.users["user"].id}'
        status, data = await self.http('GET', path+'/pdf?token='+self.tokens['admin'], 'admin')
        self.assertEqual(status, 200, data)
        self.assertTrue(data.startswith(b'%PDF-'))
        # fpdf output includes image data and a nonempty document, not a mocked generator.
        self.assertIn(b'/Subtype /Image', data)
        status, _ = await self.http('DELETE', path, 'admin')
        self.assertEqual(status, 200)
        status, _ = await self.http('GET', f'/events/{self.event.id}/release-form/mine')
        self.assertEqual(status, 404)

    async def test_T4_unregistered_cannot_sign_or_read_other_waiver(self):
        await self.sign()
        status, _ = await self.http('POST', f'/events/{self.event.id}/release-form/sign', 'viewer', body=self.waiver)
        self.assertEqual(status, 403)
        status, _ = await self.http('GET', f'/events/{self.event.id}/release-form/mine', 'viewer')
        self.assertEqual(status, 404)
        path = f'/admin/events/{self.event.id}/releases/{self.users["user"].id}/pdf'
        status, _ = await self.http('GET', path+'?token='+self.tokens['user'])
        self.assertEqual(status, 403)

    async def test_T4_empty_signature_is_rejected(self):
        status, _ = await self.http('POST', f'/events/{self.event.id}/release-form/sign',
                                    body={**self.waiver, 'signature_base64':''})
        self.assertIn(status, (400, 422), 'R15: empty signature must not create a signed waiver')
        self.assertEqual(self.db.query(SignedRelease).count(), 0)

    async def test_T8_import_authorization_through_http(self):
        for role, expected in [(None, 401), ('user', 403), ('race_director', 403), ('admin', 200)]:
            status, data = await self.import_csv(role)
            self.assertEqual(status, expected, data)

    async def test_T8_valid_import_preserves_other_events(self):
        # A valid replacement must not remove another event's classification.
        from db.models import Event
        other = Event(title='Other', location='Other', event_date=self.event.event_date)
        self.db.add(other)
        self.db.flush()
        self.db.add(EventResult(event_id=other.id, position=1, driver_name='Other', is_official=True))
        self.db.commit()
        status, data = await self.import_csv()
        self.assertEqual(status, 200, data)
        self.assertEqual(json.loads(data)['imported'], 1)
        self.assertEqual(self.db.query(EventResult).filter_by(event_id=other.id).one().driver_name, 'Other')

    async def test_T10_durable_records_after_engine_reopen(self):
        await self.sign()
        status, _ = await self.import_csv()
        self.assertEqual(status, 200)
        self.db.close()
        self.engine.dispose()
        reopened = create_engine(self.url)
        try:
            with Session(reopened) as db:
                self.assertEqual(db.query(SignedRelease).count(), 1)
                self.assertEqual(db.query(EventRegistration).count(), 1)
                self.assertEqual(db.query(EventResult).count(), 1)
        finally:
            reopened.dispose()

    async def test_T12_demoted_token_cannot_download_waiver(self):
        await self.sign()
        self.users['admin'].role = 'user'
        self.db.commit()
        path = f'/admin/events/{self.event.id}/releases/{self.users["user"].id}/pdf?token={self.tokens["admin"]}'
        status, _ = await self.http('GET', path, 'admin')
        self.assertIn(status, (401, 403), 'R3: waiver download must check current database role')

    async def test_T12_deleted_account_cannot_download_waiver(self):
        await self.sign()
        token = self.tokens['admin']
        self.db.delete(self.users['admin'])
        self.db.commit()
        path = f'/admin/events/{self.event.id}/releases/{self.users["user"].id}/pdf?token={token}'
        status, _ = await self.http('GET', path, 'admin')
        self.assertEqual(status, 401, 'R3: deleted identity must not retain PDF access')

    async def test_T12_private_database_is_not_public_static_asset(self):
        # Use the real mounted StaticFiles handler but redirect it to synthetic files only.
        from main import app
        static = next(route.app for route in app.routes if getattr(route, 'path', None) == '/static')
        fake = Path(self.directory.name)/'public-fixture'
        fake.mkdir()
        (fake/'kart_timing.db').write_bytes(b'SYNTHETIC PRIVATE DATA')
        isolated = FastAPI()
        isolated.mount('/static', static)
        with patch.object(static, 'all_directories', [str(fake)]), patch.object(static, 'directory', str(fake)):
            status, _ = await request(isolated, 'GET', '/static/kart_timing.db')
        self.assertIn(status, (401, 403, 404), 'Q4: database files must not be served anonymously')

    async def test_A3_foreign_team_edit_denied(self):
        self.db.add(EventRegistration(event_id=self.event.id, user_id=self.users['admin'].id,
                                     team_id='foreign-team', team_name='Original', is_team_leader=True))
        self.db.commit()
        status, _ = await self.http('PUT', f'/events/{self.event.id}/registrations/team/foreign-team',
                                    body={'team_name':'Changed', 'member_emails':[]})
        self.assertEqual(status, 403)
        self.assertEqual(self.db.query(EventRegistration).filter_by(team_id='foreign-team').one().team_name, 'Original')

    async def test_T5_shared_source_and_switch_preserve_other_client(self):
        from scraper.session import ScraperSession
        a, b = Mock(), Mock()
        loop = asyncio.get_running_loop()
        with patch.object(manager, 'client_url', {}), patch.object(manager, 'client_event', {}), \
             patch.dict(manager.sessions, {}, clear=True), patch.object(ScraperSession, 'start'), \
             patch.object(ScraperSession, '_delete_saved_file'):
            first = manager.subscribe_client(a, 'source-A', loop)
            second = manager.subscribe_client(b, 'source-A', loop)
            self.assertIs(first, second)
            self.assertEqual(first.subscriber_count, 2)
            new = manager.subscribe_client(a, 'source-B', loop)
            self.assertEqual(first.subscriber_count, 1)
            self.assertEqual(manager.client_url[b], 'source-A')
            manager.unsubscribe_client(a)
            self.assertEqual(new.subscriber_count, 0)
            self.assertIsNotNone(new._stop_timer)
            new._cancel_pending_stop()
            new._idle_stop_check()
            self.assertNotIn('source-B', manager.sessions)
            manager.unsubscribe_client(b)
            first._cancel_pending_stop()

    async def test_T4_upload_exact_limit_and_one_byte_over(self):
        from services import pdf_router
        from fastapi import HTTPException
        limit = 10 * 1024 * 1024
        self.assertEqual(pdf_router.MAX_BYTES, limit)
        class Upload:
            def __init__(self, size): self.size = size
            async def stream(self):
                yield b'%PDF-'
                yield b'0' * (self.size - 5)
        with patch.object(pdf_router, 'PDF_DIR', Path(self.directory.name)/'pdfs'):
            result = await pdf_router.publish_pdf(Upload(limit), {'sub':'1'})
            filename = result['path'].split('/')[-1]
            self.assertEqual(len(pdf_router.view_pdf(filename).body), limit)
            with self.assertRaises(HTTPException) as error:
                await pdf_router.publish_pdf(Upload(limit+1), {'sub':'1'})
            self.assertEqual(error.exception.status_code, 413)

    async def test_T2_full_individual_event_enters_waitlist(self):
        self.event.max_participants = 1
        self.db.commit()
        status, data = await self.http('POST', f'/events/{self.event.id}/register', 'race_director', raw=b'null')
        self.assertEqual(status, 201, data)
        self.assertEqual(json.loads(data)['status'], 'waitlist')

    async def test_T5_simulator_normalization_and_factory(self):
        from scraper.providers import simulator
        from scraper.factory import get_scraper_for_url
        path = Path(self.directory.name)/'timing.json'
        payload = {'headers':['Kart', 'Laps', 'Last'], 'rows':[['7', '2', '54.123']], 'extra':'ignored'}
        path.write_text(json.dumps(payload))
        with patch.object(simulator, 'SIMULATOR_JSON_PATH', path):
            scraper = get_scraper_for_url('https://simulator')
            self.assertIsInstance(scraper, simulator.SimulatorScraper)
            scraper.setup('https://simulator')
            self.assertEqual(scraper.scrape(), {k:payload[k] for k in ('headers', 'rows')})
            scraper.teardown()

    async def test_T6_assignment_conflict_preserves_existing_entries(self):
        path = f'/live/{self.event.id}/karts'
        for team, kart in [('first', 7), ('second', 8)]:
            status, data = await self.http('POST', path, 'race_director', body={'team_id':team, 'kart_number':kart})
            self.assertEqual(status, 201, data)
        status, _ = await self.http('POST', path, 'race_director', body={'team_id':'second', 'kart_number':7})
        self.assertEqual(status, 409)
        from db.models import LiveKartAssignment
        self.assertEqual({(r.team_id,r.kart_number) for r in self.db.query(LiveKartAssignment)}, {('first',7),('second',8)})

    async def test_T7_warning_threshold_creates_configured_penalty(self):
        from db.models import PenaltyType, RacePenalty
        self.db.add_all([
            PenaltyType(code='test-warning',name='Warning',action='warning',warning_threshold=2,auto_penalty_code='test-time'),
            PenaltyType(code='test-time',name='Time',action='time_added',default_seconds=10),
        ])
        self.db.commit()
        for count in range(1,3):
            status, data = await self.http('POST', f'/live/{self.event.id}/penalties', 'race_director',
                                           body={'kart_number':7, 'penalty_type':'test-warning'})
            self.assertEqual(status, 201, data)
            self.assertEqual(self.db.query(RacePenalty).filter_by(penalty_type='test-time').count(), 0 if count==1 else 1)
        self.assertEqual(self.db.query(RacePenalty).filter_by(penalty_type='test-time').one().seconds, 10)
