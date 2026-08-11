# Task 2 Report — Supabase metadata schema, RLS, SQLAlchemy readiness

Date: 2026-08-11
Worktree: `/Users/enkidu/Documents/ChatGPT/StudyFlow/.worktrees/studyflow-mvp`
Branch: current branch in linked worktree

## Changed files

- `infra/.env.example`
- `server/alembic.ini`
- `server/app/db/__init__.py`
- `server/app/db/config.py`
- `server/app/db/context.py`
- `server/app/db/engine.py`
- `server/app/db/models.py`
- `server/app/db/repositories.py`
- `server/app/health/routes.py`
- `server/app/main.py`
- `server/migrations/env.py`
- `server/migrations/versions/001_sync_metadata.py`
- `server/pyproject.toml`
- `server/tests/conftest.py`
- `server/tests/test_db_config.py`
- `server/tests/test_db_schema.py`
- `server/tests/test_health.py`

## What changed

- Added SQLAlchemy async DB configuration and engine creation for `STUDYFLOW_DATABASE_URL`, with explicit configuration errors and SQLite rejection.
- Added request-scoped `AccountContext(account_id, device_id)`.
- Added SQLAlchemy models for `accounts`, `devices`, and `sync_operations`.
- Added `SyncOperationRepository.insert_operation(...)` with `(account_id, operation_id)` idempotency and transaction-scoped `app.account_id` RLS context.
- Added Alembic migration scaffolding plus `001_sync_metadata` for schema creation, `server_sequence` identity, indexes, and RLS policies using `NULLIF(current_setting('app.account_id', true), '')::uuid`.
- Switched readiness from a static 503 stub to a dependency-backed readiness probe.
- Added integration fixtures that skip deterministically with an explicit configuration reason when `STUDYFLOW_TEST_DATABASE_URL` is absent.
- Added `.env.example` placeholders for the Supabase session pooler runtime URL and isolated integration-test database URL.
- Added `server/alembic.ini` so the required `poetry run alembic upgrade head` command works without inventing local config.

## TDD / command log

### Red

1. Initial Task 2 target before implementation:

```text
$ cd server && poetry run pytest -m integration tests/test_db_schema.py -q
sF
FAILED tests/test_db_schema.py::test_readiness_reports_database_status[asyncio]
1 failed, 1 skipped
```

Meaning:
- readiness was still returning `503`
- schema verification skipped cleanly because `STUDYFLOW_TEST_DATABASE_URL` was not configured

### Green / verification

2. Focused local verification:

```text
$ cd server && poetry run pytest tests/test_health.py tests/test_db_config.py tests/test_db_schema.py -q
....ssss
4 passed, 4 skipped in 0.01s
```

3. Integration-only target in the current environment:

```text
$ cd server && poetry run pytest -m integration tests/test_db_schema.py -q
ssss
4 skipped in 0.00s
```

Skip reason implemented in fixtures:
- `STUDYFLOW_TEST_DATABASE_URL is not set; configure an isolated PostgreSQL database for integration tests.`

4. Alembic CLI behavior without runtime DB config:

```text
$ cd server && poetry run alembic upgrade head
RuntimeError: STUDYFLOW_DATABASE_URL is not set. Configure the Supabase session pooler URL before running Alembic commands.
```

This is intentional in the current environment and confirms explicit config failure instead of fallback behavior.

5. Diff hygiene:

```text
$ git diff --check
[no output]
```

## Security checks

- No credentials were added, printed, or committed.
- `infra/.env.example` contains placeholders only.
- Runtime DB access requires `STUDYFLOW_DATABASE_URL`; missing config fails explicitly.
- SQLite / non-PostgreSQL URLs are rejected for the FastAPI runtime path.
- RLS is enabled and forced on `accounts`, `devices`, and `sync_operations`.
- Policies use the required request-scoped `app.account_id` lookup:
  - `NULLIF(current_setting('app.account_id', true), '')::uuid`
- The server repository is the component that sets the transaction-local account context.
- No auth routes, sync routes, client DB access, or later AI/scheduler behavior were implemented.

## Self-review

Manual self-review was used because a reviewer subagent was not available in this harness.

Requirement coverage:

- Supabase PostgreSQL readiness path: implemented.
- Session-pooler-oriented env template: implemented.
- SQLAlchemy async engine and models: implemented.
- Alembic migration and RLS policies: implemented.
- Request-scoped `app.account_id` RLS context: implemented.
- Repository idempotency contract: implemented and covered by an integration test.
- Deterministic integration skip when real test DB env is absent: implemented.
- Explicit configuration message when runtime DB env is absent: implemented.
- No auth, sync API surface, client Supabase access, or scheduler/AI behavior: preserved.

Extra implementation note:

- `server/alembic.ini` was added even though it was not listed in the brief because the required CLI command `poetry run alembic upgrade head` otherwise fails before reaching the migration environment.

## Concerns

- Live verification against a real Supabase database could not run in this environment because `STUDYFLOW_TEST_DATABASE_URL` and `STUDYFLOW_DATABASE_URL` were not configured.
- The integration fixture assumes the provided `STUDYFLOW_TEST_DATABASE_URL` points to an isolated database that is safe to migrate.
