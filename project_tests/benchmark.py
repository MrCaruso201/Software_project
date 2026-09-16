#!/usr/bin/env python3
"""Reduced local measurements, NOT the full T11 deployment/load acceptance."""
import asyncio
from datetime import datetime, timedelta, timezone
import json
import math
from pathlib import Path
import time
from unittest.mock import AsyncMock, patch

import run  # Configure test-only JWT and module search paths before backend imports.
from acceptance_support import BackendFixture
from db.models import LiveKartAssignment, RacePenalty, PenaltyType
from live import stint_monitor
from ws import manager

async def main():
    fixture = BackendFixture()
    fixture.setUp()
    try:
        durations = []
        async def client(index):
            for endpoint in ['/auth/me', '/events/', '/events/registrations/me']:
                start = time.perf_counter()
                status, _ = await fixture.http('GET', endpoint)
                assert status == 200, (endpoint, status)
                durations.append(time.perf_counter()-start)
        await asyncio.gather(*(client(i) for i in range(5)))
        p95 = sorted(durations)[math.ceil(len(durations)*.95)-1]
        text = 'Posizione,Pilota\n'+''.join(f'{i},Synthetic {i}\n' for i in range(1,201))
        start = time.perf_counter()
        status, data = await fixture.import_csv(text=text)
        csv_seconds = time.perf_counter()-start
        assert status == 200 and json.loads(data)['imported'] == 200

        # Synthetic sinks exercise fan-out only; no TCP/TLS or actual mobile receipt.
        deliveries = []
        class Sink:
            async def send_text(self, data): deliveries.append(time.perf_counter())
        clients = {Sink(): f'source-{i%3}' for i in range(50)}
        start = time.perf_counter()
        with patch.object(manager, 'client_url', clients):
            await asyncio.gather(*(manager.broadcast_to_url(f'source-{i}', {'type':'timing_update'}) for i in range(3)))
        fanout = max(deliveries)-start
        assert len(deliveries)==50

        fixture.event.race_status = 'running'
        fixture.event.max_stint_duration = 1
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        fixture.db.add(PenaltyType(code='stint_time', name='Stint', action='time_added', default_seconds=10))
        fixture.db.add(LiveKartAssignment(event_id=fixture.event.id, team_id='test', kart_number=7,
                                         stint_elapsed_seconds=0, stint_last_resume=now-timedelta(seconds=59.5)))
        fixture.db.commit()
        crossing = time.perf_counter()+.5
        with patch.object(stint_monitor, 'SessionLocal', fixture.factory), \
             patch.object(stint_monitor, 'broadcast_to_event', AsyncMock()):
            task = asyncio.create_task(stint_monitor.monitor_stints())
            try:
                deadline = time.perf_counter()+4
                while time.perf_counter()<deadline:
                    with fixture.factory() as db:
                        if db.query(RacePenalty).count(): break
                    await asyncio.sleep(.02)
                else:
                    raise AssertionError('Monitor did not assess within local 4-second observation window')
                assessment_delay = time.perf_counter()-crossing
            finally:
                task.cancel()
                try: await task
                except asyncio.CancelledError: pass
        record = {'utc': datetime.now(timezone.utc).isoformat(),
                  'scope': 'Local synthetic, no production server, network, provider or iOS UI; not full T11 acceptance',
                  'concurrent_coroutines':5, 'api_requests':15, 'api_p95_seconds':p95,
                  'csv_rows':200, 'csv_single_run_seconds':csv_seconds,
                  'synthetic_sources':3, 'synthetic_recipients':50, 'fanout_max_seconds':fanout,
                  'stint_delay_after_threshold_seconds_approx':assessment_delay,
                  'P3':'NOT EXECUTED: requires iOS UI/network fault observation'}
        path = Path(__file__).parent/'evidence'/'local_benchmark.json'
        path.write_text(json.dumps(record,indent=2)+'\n')
        print(json.dumps(record,indent=2))
    finally:
        fixture.doCleanups()

if __name__=='__main__':
    import os
    import threading
    watchdog = threading.Timer(30, lambda: os._exit(124))
    watchdog.daemon = True
    watchdog.start()
    try:
        asyncio.run(main())
    finally:
        watchdog.cancel()
