#!/usr/bin/env python3
"""Run isolated backend tests and retain per-case evidence. No server startup."""
import argparse
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import secrets
import subprocess
import sys
import time
import unittest
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
# Set before dotenv/auth imports; never use an operational JWT signing key.
os.environ['JWT_SECRET'] = secrets.token_urlsafe(48)
sys.path.insert(0, str(REPO / 'python_scraper_server'))
sys.path.insert(0, str(ROOT / 'backend'))

class EvidenceResult(unittest.TextTestResult):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.records = []
        self.started = {}

    def startTest(self, test):
        self.started[test.id()] = time.perf_counter()
        super().startTest(test)

    def record(self, test, status, detail=''):
        self.records.append({'id': test.id(), 'status': status,
                             'seconds': time.perf_counter() - self.started.get(test.id(), time.perf_counter()),
                             'detail': detail})

    def addSuccess(self, test):
        super().addSuccess(test)
        self.record(test, 'PASS')

    def addFailure(self, test, err):
        super().addFailure(test, err)
        self.record(test, 'FAIL', self._exc_info_to_string(err, test))

    def addError(self, test, err):
        super().addError(test, err)
        self.record(test, 'ERROR', self._exc_info_to_string(err, test))

    def addSkip(self, test, reason):
        super().addSkip(test, reason)
        self.record(test, 'SKIP', reason)

    def addSubTest(self, test, subtest, err):
        super().addSubTest(test, subtest, err)
        if err is not None:
            self.record(subtest, 'FAIL' if issubclass(err[0], test.failureException) else 'ERROR',
                        self._exc_info_to_string(err, test))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pattern', default='test_*.py')
    args = parser.parse_args()
    output = ROOT / 'evidence'
    output.mkdir(exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    text = io.StringIO()
    with contextlib.redirect_stdout(text), contextlib.redirect_stderr(text):
        suite = unittest.defaultTestLoader.discover(str(ROOT / 'backend'), pattern=args.pattern)
        result = unittest.TextTestRunner(stream=text, verbosity=2, resultclass=EvidenceResult).run(suite)
    hashes = {str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted((REPO/'python_scraper_server').rglob('*.py')) if '__pycache__' not in str(p)}
    for p in [REPO/'DD_Race_Manager.md', REPO/'RASD_Race_Manager.md', *sorted(ROOT.rglob('*.py'))]:
        hashes[str(p.relative_to(REPO))] = hashlib.sha256(p.read_bytes()).hexdigest()
    report = {'utc': stamp, 'python': platform.python_version(), 'platform': platform.platform(),
              'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip(),
              'pattern': args.pattern, 'tests_run': result.testsRun,
              'failures': len(result.failures), 'errors': len(result.errors), 'skipped': len(result.skipped),
              'successful': result.wasSuccessful(), 'cases': result.records, 'sha256': hashes}
    (output/f'{stamp}.json').write_text(json.dumps(report, indent=2)+'\n')
    (output/f'{stamp}.log').write_text(text.getvalue())
    print(f"{result.testsRun} tests: {len(result.failures)} failures, {len(result.errors)} errors, {len(result.skipped)} skips")
    print(f'Evidence: {output / stamp}')
    return 0 if result.wasSuccessful() else 1

if __name__ == '__main__':
    sys.exit(main())
