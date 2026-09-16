# DD/RASD verification

This directory is the single location for the project's backend tests and their execution evidence. The 13 existing modules (69 tests) were moved unchanged from `python_scraper_server/tests/` into `backend/`. An additional module contains 25 DD/RASD acceptance tests. No application fixes are included.

- [Test report](TEST_REPORT.md): concise evaluation, T1–T12/A1–A10 coverage, failures and remaining checks.
- [Previously executed tests](ALREADY_EXECUTED.md): tests previously run but without individual outcomes recorded in the supplied DD/RASD.
- [Complete inventory](TEST_INVENTORY.md): per-test outcome and mapping.
- [Evidence](evidence/): raw unittest logs, machine-readable results, source/document SHA-256 hashes and reduced benchmark measurements.

## Run from the repository root

```sh
.venv/bin/python project_tests/run.py
.venv/bin/python project_tests/run.py --pattern test_document_acceptance.py
.venv/bin/python project_tests/run.py --pattern test_stint_monitor.py
.venv/bin/python project_tests/benchmark.py
```

Alternatively use `python` from an environment with `python_scraper_server/requirements.txt` installed (PDF image tests also use Pillow, provided through fpdf2). The runner configures import paths and a random test-only JWT secret before importing backend modules; no operational `.env` credential is needed. Use this runner rather than direct unittest discovery from the root.

The runner writes timestamped JSON/log files and returns nonzero when any assertion fails. **The full suite currently returns 1 because four acceptance checks expose application defects.** These are real failing assertions, not skipped or expected-failure tests. The existing 69 regression tests still pass.

Fixtures use temporary/in-memory SQLite databases and synthetic identities/signatures. The new HTTP checks execute real FastAPI routes and authentication dependencies in-process through ASGI. They do not start the application lifespan, Bonjour, provider browsers, a network server, or operational background jobs. The static-file check redirects the real handler to a temporary synthetic directory; it never downloads the actual database.

The reduced benchmark explicitly starts the stint monitor against its temporary fixture and cancels it afterward. Its 30-second watchdog returns exit code 124 if the process cannot finish. It measures a short synthetic workload, not production capacity. It overwrites `evidence/local_benchmark.json`; copy that file before keeping multiple benchmark samples.

## Interpreting results

A passing test establishes only the assertions it executes. Calling a handler directly does not verify its FastAPI authorization dependencies; new sensitive-route tests therefore use ASGI. Fake WebSocket sinks verify routing but not real TCP/WSS delivery. Reopening a SQLite engine verifies committed storage but not a full server/device restart.

The report is a dated review of the recorded run. Rerunning scripts creates new evidence; it does not automatically rewrite the reviewed report or inventory. The original DD/RASD are preserved as input specifications.
