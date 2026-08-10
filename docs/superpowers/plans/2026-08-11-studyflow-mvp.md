# StudyFlow MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the first usable StudyFlow loop: Android and macOS can create tasks and schedule blocks offline, record focus sessions, synchronize encrypted records through the Debian 12 FastAPI service backed by Supabase PostgreSQL, and request rule-validated AI schedule suggestions.

**Architecture:** Flutter owns the shared UI, local domain state, encrypted Drift database, and offline operation queue. FastAPI is the only public application API and stores only encrypted operation payloads plus synchronization metadata in Supabase PostgreSQL. Caddy terminates the VPS web entry point behind the Cloudflare-proxied API domain and forwards traffic to FastAPI; platform-specific notifications and permission checks are isolated behind Kotlin and Swift adapters.

**Tech Stack:** Flutter stable/Dart, Riverpod, GoRouter, Drift, encrypted SQLite adapter, Kotlin, Swift, Python 3.12, FastAPI, Pydantic v2, SQLAlchemy 2, Alembic, Poetry, PostgreSQL/Supabase, Docker Compose, Caddy, Cloudflare DNS proxy.

## Global Constraints

- Android and macOS are the first supported clients; Windows, Linux, and iOS must remain possible through platform contracts.
- The reference Android device is iQOO Z9 Turbo, model `V2352A`, OriginOS 6 build `PD2352B_A_16.2.15.0.W10.V000L1`.
- Debian 12 Bookworm runs Docker Engine, Docker Compose, FastAPI, and Caddy; PostgreSQL runs in Supabase, not on the VPS.
- Flutter clients never connect directly to Supabase and never contain database passwords, `service_role`, or other management keys.
- Task text, schedule notes, check-in text, and AI input text are encrypted on the client before upload.
- The server stores only synchronization metadata and opaque encrypted payloads; AI requests receive only the minimum structured data needed for the current suggestion.
- LLM output is never allowed to write the database directly; Pydantic validation and deterministic policy checks precede every user-visible recommendation or schedule change.
- L0/L1 suggestions require no automatic device takeover; L2 schedule mutation requires confirmation; L3 requires at least 14 consecutive days of valid records and a new explicit authorization.
- Device-control work is limited to reminders, focus mode, and user-revocable restrictions; arbitrary remote control, screen contents, window contents, and raw browsing history are out of scope.
- Every task ends with a focused test command and a small commit; no task may silently discard local changes or hide a failed synchronization state.

## File and Module Map

The repository starts with the committed design document only. The implementation will add these bounded modules:

- `apps/client/`: Flutter application, screens, Riverpod providers, local database, sync engine, and native platform channels.
- `packages/domain/`: shared Dart value objects and deterministic domain rules that do not perform I/O.
- `packages/sync_contract/`: versioned operation, pull, push, conflict, and error models shared by the client and contract tests.
- `packages/platform_contract/`: capability interfaces and normalized permission/error results for Android, macOS, Windows, Linux, and iOS.
- `server/app/health/`: liveness and readiness endpoints.
- `server/app/auth/`: account login, access tokens, device registration, and one-time pairing.
- `server/app/db/`: SQLAlchemy engine, request-scoped account context, and repositories.
- `server/app/sync/`: encrypted operation ingestion, pull cursors, idempotency, and metadata validation.
- `server/app/scheduler/`: sleep-window and schedule policy rules.
- `server/app/ai/`: structured AI gateway, redaction boundary, recommendation validation, and audit metadata.
- `server/migrations/`: Alembic migrations and RLS policies for Supabase PostgreSQL.
- `infra/`: Docker Compose, Caddy, environment template, health checks, and encrypted backup scripts.
- `tests/contract/`: JSON contract fixtures consumed by Python and Dart tests.
- `tests/integration/`: service/database and offline synchronization scenarios.
- `tests/device/`: manual test matrices and scripts that do not require secrets in the repository.

---

### Task 1: Bootstrap the repository and executable test baselines

**Files:**
- Create: `server/pyproject.toml`
- Create: `server/app/__init__.py`
- Create: `server/app/health/routes.py`
- Create: `server/app/main.py`
- Create: `server/tests/test_health.py`
- Create: `apps/client/pubspec.yaml`
- Create: `apps/client/lib/main.dart`
- Create: `packages/domain/pubspec.yaml`
- Create: `packages/domain/lib/domain.dart`
- Create: `packages/sync_contract/pubspec.yaml`
- Create: `packages/platform_contract/pubspec.yaml`
- Create: `packages/platform_contract/lib/platform_contract.dart`
- Create: `.gitignore`
- Create: `README.md`

**Interfaces:**
- Produces `server.app.main.app`, `GET /health/live`, `GET /health/ready`, and four Dart packages that can be resolved with path dependencies.
- `GET /health/live` returns `{"status":"ok"}` without contacting a database.
- `GET /health/ready` returns `{"status":"ok","database":"ok"}` once the database adapter exists; before Task 2 it returns HTTP 503 with `{"status":"not_ready","database":"not_configured"}`.

- [ ] **Step 1: Write the failing Python health test**

```python
from fastapi.testclient import TestClient

from server.app.main import app


def test_liveness_is_available_without_database() -> None:
    response = TestClient(app).get("/health/live")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
```

- [ ] **Step 2: Run the focused test to verify the baseline fails**

Run: `cd server && poetry run pytest tests/test_health.py::test_liveness_is_available_without_database -q`

Expected: FAIL because the `server` package and `app` object do not exist.

- [ ] **Step 3: Add the minimal FastAPI application and dependency manifests**

Implement `server/app/main.py` with a `FastAPI(title="StudyFlow API")` instance and a liveness route. Set Python constraints to `>=3.12,<3.13`; include FastAPI, Uvicorn, Pydantic, SQLAlchemy, asyncpg, Alembic, pytest, and httpx in `pyproject.toml`. Set the Flutter app to depend on Riverpod, GoRouter, Drift, `sqlite3`, and the three local packages; keep platform-specific packages behind adapters. Add package entrypoints that export no I/O and run `flutter create --project-name studyflow --org com.studyflow --platforms=android,ios,macos,windows,linux .` from `apps/client` so all future platform folders exist from the first commit.

- [ ] **Step 4: Run Python and Dart dependency checks**

Run: `cd server && poetry install && poetry run pytest tests/test_health.py -q`

Run: `cd apps/client && flutter pub get`

Expected: the health test passes and all Dart path dependencies resolve.

- [ ] **Step 5: Commit the bootstrap**

```bash
git add .gitignore README.md server apps packages
git commit -m "chore: bootstrap StudyFlow clients and API"
```

### Task 2: Add Supabase metadata schema, RLS, and database readiness

**Files:**
- Create: `server/app/db/config.py`
- Create: `server/app/db/engine.py`
- Create: `server/app/db/context.py`
- Create: `server/app/db/models.py`
- Create: `server/app/db/repositories.py`
- Create: `server/tests/conftest.py`
- Create: `server/migrations/env.py`
- Create: `server/migrations/versions/001_sync_metadata.py`
- Create: `server/tests/test_db_schema.py`
- Modify: `server/app/main.py`
- Create: `infra/.env.example`

**Interfaces:**
- `create_engine_from_env() -> AsyncEngine` reads `STUDYFLOW_DATABASE_URL` and configures SQLAlchemy 2 asyncpg pooling.
- `AccountContext(account_id: UUID, device_id: UUID)` is the request-scoped database identity.
- `SyncOperationRepository.insert_operation(context, operation) -> InsertResult` is idempotent by `(account_id, operation_id)`.
- The migration creates `accounts`, `devices`, and `sync_operations`; `sync_operations.server_sequence` is a monotonically increasing identity used by pull cursors.
- `server/tests/conftest.py` provides the named `database` fixture for an isolated test database and the named `client` fixture with a transaction-scoped readiness dependency override.

- [ ] **Step 1: Write the schema and readiness tests**

```python
import pytest


@pytest.mark.integration
async def test_sync_metadata_has_opaque_payload_columns(database):
    columns = await database.columns("sync_operations")

    assert {"account_id", "operation_id", "record_id", "server_sequence"}.issubset(columns)
    assert {"payload_nonce", "payload_ciphertext", "is_tombstone"}.issubset(columns)


@pytest.mark.integration
async def test_readiness_reports_database_status(client):
    response = await client.get("/health/ready")

    assert response.status_code == 200
    assert response.json()["database"] == "ok"
```

The `database` and `client` fixtures are concrete async fixtures in `server/tests/conftest.py`; the suite skips only when `STUDYFLOW_TEST_DATABASE_URL` is absent and prints that configuration reason.

- [ ] **Step 2: Run the schema test before the migration**

Run: `cd server && poetry run pytest -m integration tests/test_db_schema.py -q`

Expected: FAIL because no database engine, migration, or tables exist. If `STUDYFLOW_DATABASE_URL` is absent, the test must fail with a configuration message rather than silently using SQLite.

- [ ] **Step 3: Implement the migration and RLS policy**

Create `sync_operations` with an opaque `bytea` nonce and ciphertext, `is_tombstone`, `created_at`, and indexed `(account_id, server_sequence)`. Enable RLS on all account-owned tables. Policies must compare `account_id` with `NULLIF(current_setting('app.account_id', true), '')::uuid`; the repository sets that value with `SET LOCAL` inside each transaction. Do not grant the Flutter client a database role.

- [ ] **Step 4: Implement readiness and verify against the real Supabase project**

Use the Supabase session pooler URL and port for the long-lived FastAPI process. Run `poetry run alembic upgrade head`, then `poetry run pytest -m integration tests/test_db_schema.py -q`. Verify that `GET /health/ready` changes from 503 to 200 and that a database query cannot read another account's rows under the request context.

- [ ] **Step 5: Commit the database foundation**

```bash
git add server infra/.env.example
git commit -m "feat: add Supabase sync metadata schema"
```

### Task 3: Define versioned encrypted sync contracts and fixtures

**Files:**
- Create: `packages/sync_contract/lib/src/operation.dart`
- Create: `packages/sync_contract/lib/src/sync_error.dart`
- Create: `packages/sync_contract/lib/sync_contract.dart`
- Create: `server/app/sync/schemas.py`
- Create: `server/tests/test_sync_schemas.py`
- Create: `tests/contract/sync_push_v1.json`
- Create: `tests/contract/sync_pull_v1.json`

**Interfaces:**
- Dart `SyncOperationV1` fields: `operationId`, `recordId`, `deviceId`, `logicalClock`, `entityType`, `payloadNonce`, `payloadCiphertext`, `isTombstone`, and `schemaVersion`.
- Python `SyncOperationV1` is a Pydantic model with the same JSON field names and base64 transport encoding.
- `POST /v1/sync/push` accepts `{ "operations": [...] }` and returns `{ "accepted": [...], "duplicates": [...], "rejected": [...] }`.
- `GET /v1/sync/pull?after=0&limit=50` returns `{ "next_cursor": integer, "operations": [...] }`; the server accepts limits from 1 through 200.
- `tests/contract/sync_push_v1.json` and `tests/contract/sync_pull_v1.json` are the single fixtures used by both Python and Dart tests; their payload values are base64 strings, not plaintext task fields.

- [ ] **Step 1: Write fixture round-trip tests**

```python
import json
from pathlib import Path

from server.app.sync.schemas import SyncOperationV1


def test_push_fixture_round_trips_without_decrypting_payload() -> None:
    fixture = json.loads(Path("../tests/contract/sync_push_v1.json").read_text())
    operation = SyncOperationV1.model_validate(fixture["operations"][0])

    assert operation.schema_version == 1
    assert operation.payload_ciphertext
    assert operation.entity_type in {"task", "schedule_block", "focus_session", "check_in"}
```

- [ ] **Step 2: Run the contract test and observe the missing models**

Run: `cd server && poetry run pytest tests/test_sync_schemas.py -q`

Expected: FAIL because the versioned Pydantic and Dart contract models are not yet defined.

- [ ] **Step 3: Implement the Python and Dart models**

Reject unknown schema versions, empty operation IDs, negative logical clocks, payloads larger than 256 KiB, and entity types outside the four MVP entities. Keep payload bytes opaque; schema validation must never decode task text.

- [ ] **Step 4: Run both contract suites**

Run: `cd server && poetry run pytest tests/test_sync_schemas.py -q`

Run: `flutter test packages/sync_contract/test`

Expected: both suites pass and serialized Python JSON matches the checked-in fixtures.

- [ ] **Step 5: Commit the sync contract**

```bash
git add packages/sync_contract server/app/sync server/tests tests/contract
git commit -m "feat: define encrypted sync contract v1"
```

### Task 4: Implement client-side key storage and encrypted local data

**Files:**
- Create: `apps/client/lib/security/key_manager.dart`
- Create: `apps/client/lib/security/payload_cipher.dart`
- Create: `apps/client/lib/storage/app_database.dart`
- Create: `apps/client/lib/storage/tables.dart`
- Create: `apps/client/lib/storage/operation_dao.dart`
- Create: `apps/client/test/security/key_manager_test.dart`
- Create: `apps/client/test/storage/operation_dao_test.dart`
- Modify: `apps/client/pubspec.yaml`

**Interfaces:**
- `KeyManager.loadOrCreateDeviceKey() -> Future<SecretKey>` stores Android material in Keystore and macOS material in Keychain through platform adapters.
- `KeyManager.createAccountDataKey() -> Future<SecretKey>` runs only during account bootstrap.
- `PayloadCipher.encrypt(plaintext, associatedData) -> Future<EncryptedPayload>` and `PayloadCipher.decrypt(payload, associatedData) -> Future<Uint8List>` use the locked, reviewed AEAD package selected by the security check in this task.
- `OperationDao.enqueue(EncryptedOperation operation) -> Future<void>` and `OperationDao.pending(limit) -> Future<List<EncryptedOperation>>` are transactional.
- `AppDatabase` exposes encrypted Drift tables for tasks, schedule blocks, focus sessions, check-ins, and pending operations.

- [ ] **Step 1: Write crypto and queue tests with fixed vectors**

```dart
test('encrypting the same payload with a fresh nonce decrypts exactly', () async {
  final keyManager = FakeKeyManager.fromBytes(List<int>.filled(32, 7));
  final cipher = PayloadCipher(keyManager);
  final encrypted = await cipher.encrypt(utf8.encode('{"title":"algebra"}'));

  expect(await cipher.decrypt(encrypted), utf8.encode('{"title":"algebra"}'));
  expect(encrypted.nonce, isNotEmpty);
});
```

- [ ] **Step 2: Run the focused tests before storage exists**

Run: `flutter test apps/client/test/security/key_manager_test.dart apps/client/test/storage/operation_dao_test.dart`

Expected: FAIL because the key manager, cipher, Drift tables, and DAO do not exist.

- [ ] **Step 3: Implement the key hierarchy and encrypted store**

Use a reviewed libsodium-compatible AEAD implementation behind `PayloadCipher`; never create a custom cipher. The security check must compile a fixed-vector test before the dependency is locked in `pubspec.lock`. Generate a unique nonce per operation, authenticate `account_id`, `record_id`, `schema_version`, and `entity_type` as associated data, and persist only ciphertext in the queue. Use the platform secure stores for device keys and make the database-open operation fail with a visible recovery error when the key is unavailable.

- [ ] **Step 4: Verify migration and queue durability**

Run the focused tests again, then run `flutter test apps/client/test/storage -r expanded`. Include a test that kills and reopens the database, confirms pending operations remain, and confirms a duplicate `operation_id` does not create a second local row.

- [ ] **Step 5: Commit encrypted local storage**

```bash
git add apps/client
git commit -m "feat: add encrypted local database and operation queue"
```

### Task 5: Implement FastAPI push/pull synchronization and idempotency

**Files:**
- Create: `server/app/auth/dependencies.py`
- Create: `server/app/sync/repository.py`
- Create: `server/app/sync/service.py`
- Create: `server/app/sync/routes.py`
- Create: `server/tests/test_sync_service.py`
- Modify: `server/app/main.py`

**Interfaces:**
- `SyncService.push(context, operations) -> PushResult` validates device ownership and stores opaque operations idempotently.
- `SyncService.pull(context, after, limit) -> PullResult` returns only operations for the authenticated account and advances by `server_sequence`.
- `POST /v1/sync/push` requires a bearer access token and `X-Device-Id`.
- `GET /v1/sync/pull` requires the same identity and never returns plaintext payload fields.

- [ ] **Step 1: Write service tests for first insert, duplicate, and cursor isolation**

```python
async def test_push_is_idempotent(sync_service, context, operation):
    first = await sync_service.push(context, [operation])
    second = await sync_service.push(context, [operation])

    assert first.accepted == [operation.operation_id]
    assert second.duplicates == [operation.operation_id]
    assert await sync_service.count_operations(context.account_id) == 1
```

- [ ] **Step 2: Run the service tests before implementing the service**

Run: `cd server && poetry run pytest tests/test_sync_service.py -q`

Expected: FAIL because the repository, service, authentication dependency, and routes are missing.

- [ ] **Step 3: Implement repository, service, and routes**

Use a database transaction for each push batch. Treat an existing `(account_id, operation_id)` as a duplicate only after comparing its ciphertext digest; reject the request if the same operation ID carries different bytes. Pull in `server_sequence` order, cap the page at 200, and return `next_cursor` equal to the last returned sequence or the input cursor when empty.

- [ ] **Step 4: Verify API behavior and plaintext absence**

Run the service tests and add a route test asserting the response JSON contains `payload_nonce` and `payload_ciphertext` but no `title`, `notes`, `feedback`, or `prompt` fields. Verify a request from another account returns HTTP 404/403 without leaking whether a record exists.

- [ ] **Step 5: Commit the synchronization API**

```bash
git add server/app server/tests
git commit -m "feat: add idempotent encrypted sync API"
```

### Task 6: Build the shared task, schedule, focus, and check-in domain layer

**Files:**
- Create: `packages/domain/lib/src/task.dart`
- Create: `packages/domain/lib/src/schedule_block.dart`
- Create: `packages/domain/lib/src/focus_session.dart`
- Create: `packages/domain/lib/src/check_in.dart`
- Create: `packages/domain/lib/src/schedule_rules.dart`
- Create: `packages/domain/test/schedule_rules_test.dart`
- Create: `apps/client/lib/features/tasks/task_repository.dart`
- Create: `apps/client/lib/features/schedule/schedule_repository.dart`

**Interfaces:**
- `Task` has `id`, `title`, `description`, `estimatedMinutes`, `priority`, `status`, `tags`, and `repeatRule`.
- `ScheduleBlock` has `id`, `start`, `end`, `kind`, `taskId`, `source`, and `isLocked`.
- `ScheduleRules.validateNoOverlap(blocks) -> List<ScheduleViolation>` rejects overlapping locked blocks and returns deterministic violations for other conflicts.
- `FocusSession.finish(end, completionMethod) -> FocusSession` is append-only and cannot mutate an existing finished session.
- `packages/domain/test/schedule_rules_test.dart` defines the `block(start, end, locked)` helper with fixed `Asia/Shanghai` dates so all rule assertions use concrete instants.

- [ ] **Step 1: Write domain rule tests**

```dart
test('locked schedule blocks cannot overlap', () {
  final result = ScheduleRules.validateNoOverlap([
    block('08:00', '09:00', locked: true),
    block('08:30', '09:30', locked: true),
  ]);

  expect(result.single.code, 'locked_block_overlap');
});
```

- [ ] **Step 2: Run the domain tests before the models exist**

Run: `flutter test packages/domain/test/schedule_rules_test.dart`

Expected: FAIL because the domain objects and validation function are missing.

- [ ] **Step 3: Implement immutable domain objects and rules**

Use UTC instants in storage and convert to the profile time zone only at the UI boundary. Enforce positive estimated duration, `end > start`, a single time zone per profile, and the minimum rest interval configured in `UserProfile`. Do not place database or network calls in `packages/domain`.

- [ ] **Step 4: Run domain and serialization tests**

Run: `flutter test packages/domain/test -r expanded`

Expected: PASS for overlap, invalid interval, locked block, repeat-rule, and finished-session immutability cases.

- [ ] **Step 5: Commit the shared domain layer**

```bash
git add packages/domain apps/client/lib/features
git commit -m "feat: add StudyFlow domain rules"
```

### Task 7: Add the offline-first sync engine and shared client state

**Files:**
- Create: `apps/client/lib/sync/sync_engine.dart`
- Create: `apps/client/lib/sync/sync_api.dart`
- Create: `apps/client/lib/sync/sync_status.dart`
- Create: `apps/client/lib/providers/app_providers.dart`
- Create: `apps/client/test/sync/sync_engine_test.dart`
- Modify: `apps/client/lib/storage/operation_dao.dart`

**Interfaces:**
- `SyncEngine.runOnce() -> Future<SyncRunResult>` performs push, pull, local apply, and cursor commit in that order.
- `SyncEngine.status -> ValueListenable<SyncStatus>` exposes `idle`, `syncing`, `offline`, `failed`, and `pendingCount`.
- `SyncApi.push()` and `SyncApi.pull()` use the Task 3 contract and return typed failures.
- `apps/client/test/sync/sync_engine_test.dart` defines `FailingSyncApi` and `testEngine(...)` as test-only implementations; production code must not depend on either helper.

- [ ] **Step 1: Write offline and retry tests**

```dart
test('network failure leaves the operation queued and exposes failure', () async {
  final engine = testEngine(api: FailingSyncApi());
  await engine.runOnce();

  expect(engine.status.value.kind, SyncStatusKind.failed);
  expect(await engine.pendingCount(), 1);
});
```

- [ ] **Step 2: Run the sync engine tests before implementation**

Run: `flutter test apps/client/test/sync/sync_engine_test.dart`

Expected: FAIL because the engine, typed API, and status model are missing.

- [ ] **Step 3: Implement operation ordering and retry behavior**

Push pending local operations first; do not delete them until the server confirms acceptance or duplicate status. Pull after the last committed cursor, decrypt locally, apply idempotently, and commit the cursor in the same local transaction as the applied records. On network, authentication, decryption, or schema errors, retain the queue and expose a categorized status with a retry action.

- [ ] **Step 4: Verify multi-device conflict behavior**

Add tests for duplicate pulls, task field-level last-write merge, simultaneous schedule-block edits producing a conflict copy, tombstone retention, and append-only focus sessions. Run `flutter test apps/client/test/sync -r expanded`.

- [ ] **Step 5: Commit the offline sync engine**

```bash
git add apps/client/lib/sync apps/client/lib/providers apps/client/test/sync
git commit -m "feat: add offline-first client synchronization"
```

### Task 8: Implement Android and macOS platform contracts and first UI shell

**Files:**
- Create: `packages/platform_contract/lib/src/platform_capabilities.dart`
- Create: `packages/platform_contract/lib/src/platform_error.dart`
- Create: `packages/platform_contract/lib/platform_contract.dart`
- Create: `apps/client/lib/platform/platform_bridge.dart`
- Create: `apps/client/android/app/src/main/kotlin/com/studyflow/app/StudyFlowPlatform.kt`
- Create: `apps/client/macos/Runner/StudyFlowPlatform.swift`
- Create: `apps/client/lib/features/home/home_screen.dart`
- Create: `apps/client/lib/features/tasks/task_list_screen.dart`
- Create: `apps/client/lib/features/tasks/task_editor_screen.dart`
- Create: `apps/client/lib/features/focus/focus_screen.dart`
- Create: `apps/client/test/platform/platform_bridge_test.dart`

**Interfaces:**
- `PlatformCapabilities.scheduleReminder()`, `startFocusSession()`, `getUsageSummary()`, `applyRestriction()`, `clearRestriction()`, and `getPermissionStatus()` return typed support and permission states.
- Unsupported platforms return `CapabilityResult.unsupported(reason: ...)`; they do not throw an unhandled platform-channel exception.
- The first UI routes are `/today`, `/tasks`, `/schedule`, `/focus`, and `/settings`.
- `platform_bridge_test.dart` defines `UnsupportedPlatform` and a minimal valid `rule` fixture; both are test-only.

- [ ] **Step 1: Write platform fallback and navigation tests**

```dart
test('unsupported restriction capability is explicit', () async {
  final result = await PlatformBridge(UnsupportedPlatform()).applyRestriction(rule);

  expect(result.kind, CapabilityResultKind.unsupported);
  expect(result.message, contains('not supported'));
});
```

- [ ] **Step 2: Run platform tests before native adapters exist**

Run: `flutter test apps/client/test/platform/platform_bridge_test.dart`

Expected: FAIL because the platform contract, bridge, and fallback implementation are missing.

- [ ] **Step 3: Implement the shared Flutter shell and native channels**

Implement task creation, schedule-block creation, manual completion, focus start/pause/finish, check-in entry, pending-sync count, and explicit permission health status. Android must request notification and exact-alarm status without assuming background survival. macOS must expose UserNotifications authorization and a visible menu-bar/background-running status. Usage summaries and restrictions return `unsupported` until their separate authorization work is completed.

- [ ] **Step 4: Run the client test suite and launch both targets**

Run: `flutter test apps/client/test packages/domain/test packages/sync_contract/test`

Run: `flutter run -d macos --target apps/client/lib/main.dart`

Run `flutter devices`, select the listed iQOO device identifier, and launch `apps/client/lib/main.dart` on that device; the exact identifier is the value printed by the command on the connected phone.

Expected: task creation and focus recording work offline on both targets; the UI displays an explicit offline/pending-sync state.

- [ ] **Step 5: Commit the first usable client loop**

```bash
git add packages/platform_contract apps/client
git commit -m "feat: add Android macOS shell and focus workflow"
```

### Task 9: Add authentication, device pairing, and recovery-key flows

**Files:**
- Create: `server/app/auth/models.py`
- Create: `server/app/auth/service.py`
- Create: `server/app/auth/routes.py`
- Create: `server/tests/test_auth_and_pairing.py`
- Create: `apps/client/lib/auth/auth_repository.dart`
- Create: `apps/client/lib/auth/pairing_screen.dart`
- Create: `apps/client/lib/auth/recovery_key_screen.dart`
- Create: `apps/client/test/auth/auth_repository_test.dart`

**Interfaces:**
- `POST /v1/auth/bootstrap` creates the single-user account and first device exactly once when presented with `STUDYFLOW_BOOTSTRAP_TOKEN`.
- `POST /v1/auth/login` returns a short-lived access token and rotating refresh token; passwords are stored as Argon2id hashes.
- `POST /v1/devices/pair` consumes a one-time six-digit code that expires after 10 minutes and returns the encrypted account-data-key envelope.
- `POST /v1/devices/revoke` revokes one device without deleting the account's encrypted records.
- `server/tests/test_auth_and_pairing.py` defines the `auth_client` fixture, which uses an isolated database and a deterministic test clock; it never contacts the production Supabase project.

- [ ] **Step 1: Write one-time bootstrap and pairing tests**

```python
async def test_pairing_code_cannot_be_reused(auth_client):
    code = await auth_client.create_pairing_code()
    first = await auth_client.pair(code)
    second = await auth_client.pair(code)

    assert first.status_code == 200
    assert second.status_code == 410
```

- [ ] **Step 2: Run authentication tests before routes exist**

Run: `cd server && poetry run pytest tests/test_auth_and_pairing.py -q`

Expected: FAIL because account, token, device, and pairing services are missing.

- [ ] **Step 3: Implement server authentication and client enrollment**

Keep the bootstrap token only in the VPS secret environment. Bind every access token to `account_id` and `device_id`; validate device status on every sync request. Encrypt the account-data-key envelope to the new device public key. Make recovery export a user-visible, one-time-confirmed file/text payload and never send the raw recovery key to the server.

- [ ] **Step 4: Verify revocation and recovery failure states**

Run server and client auth tests. Confirm a revoked device receives HTTP 401 on push and pull, a second bootstrap is rejected, an expired code cannot pair, and losing the recovery key produces an explicit non-recoverable message.

- [ ] **Step 5: Commit authentication and pairing**

```bash
git add server/app/auth server/tests apps/client/lib/auth apps/client/test/auth
git commit -m "feat: add account device pairing and recovery flow"
```

### Task 10: Implement deterministic sleep and schedule policy rules

**Files:**
- Create: `server/app/scheduler/models.py`
- Create: `server/app/scheduler/rules.py`
- Create: `server/app/scheduler/routes.py`
- Create: `server/tests/test_scheduler_rules.py`
- Create: `apps/client/lib/features/checkins/check_in_screen.dart`
- Create: `apps/client/test/features/checkins/check_in_screen_test.dart`

**Interfaces:**
- `SleepProfile` contains age range, time zone, target wake time, target sleep duration, and adjustment step.
- `SchedulePolicy.propose(profile, history, existing_blocks) -> ScheduleProposal` returns candidate changes plus violations.
- `ScheduleProposal` includes `proposal_id`, `original_blocks`, `candidate_blocks`, `reason_codes`, `requires_confirmation`, and `created_at`.
- `POST /v1/schedule/proposals/validate` validates a proposal but does not persist it.
- `propose_for_history(...)` in the test code constructs a `SleepProfile`, two valid historical check-ins, and one unlocked future block; it is not part of the server API.

- [ ] **Step 1: Write policy tests**

```python
def test_sleep_adjustment_is_small_and_targeted():
    proposal = propose_for_history(
        wake_time="07:30+08:00",
        sleep_duration_minutes=420,
        adjustment_step_minutes=15,
    )

    assert abs(proposal.sleep_start_delta_minutes) <= 15
    assert proposal.requires_confirmation is True
```

- [ ] **Step 2: Run the policy tests before implementation**

Run: `cd server && poetry run pytest tests/test_scheduler_rules.py -q`

Expected: FAIL because the policy types and deterministic rule engine are missing.

- [ ] **Step 3: Implement the rule engine and check-in flow**

Anchor proposals to the target wake time, preserve locked blocks, reject overlaps, require the configured minimum rest interval, and adjust by 15–30 minutes per proposal. Use age range only as a general behavior boundary; do not diagnose sleep disorders. If records show repeated severe sleep deprivation or abnormal daytime sleepiness, return a professional-help reason code and no automatic adjustment.

- [ ] **Step 4: Verify confirmation, undo, and timezone behavior**

Run server and Flutter tests. Add a test that an L2 proposal cannot change the stored schedule until confirmation, and that undo restores the exact original blocks. Test a daylight-saving transition with UTC storage and local-time presentation.

- [ ] **Step 5: Commit the deterministic schedule engine**

```bash
git add server/app/scheduler server/tests apps/client/lib/features/checkins apps/client/test/features/checkins
git commit -m "feat: add deterministic sleep and schedule rules"
```

### Task 11: Add the AI Gateway and L1 recommendation audit flow

**Files:**
- Create: `server/app/ai/models.py`
- Create: `server/app/ai/redaction.py`
- Create: `server/app/ai/provider.py`
- Create: `server/app/ai/service.py`
- Create: `server/app/ai/routes.py`
- Create: `server/tests/test_ai_gateway.py`
- Create: `apps/client/lib/features/ai/ai_repository.dart`
- Create: `apps/client/lib/features/ai/recommendation_screen.dart`
- Create: `apps/client/test/features/ai/recommendation_screen_test.dart`

**Interfaces:**
- `AiInputSummary` contains only task IDs/titles needed for the current prompt, schedule metrics, focus completion metrics, sleep/check-in aggregates, and the explicit permission level.
- `AiProvider.generate_plan(summary) -> AiRecommendationDraft` returns structured JSON with `summary`, `candidate_changes`, `reason_codes`, and `confidence`.
- `AiService.generate_l1(context, summary) -> AIRecommendation` stores only a redacted audit summary, model/provider identifier, policy result, and user decision metadata.
- `POST /v1/ai/recommendations` returns a recommendation and never mutates tasks or schedule blocks.
- `server/tests/test_ai_gateway.py` defines `fake_provider` and `summary_with_sensitive_fields()` as test-only fixtures; the provider records its structured input for the redaction assertion.

- [ ] **Step 1: Write redaction and malformed-output tests**

```python
async def test_ai_input_excludes_raw_activity_and_secrets(fake_provider):
    await generate_recommendation(summary_with_sensitive_fields())

    prompt = fake_provider.last_input
    assert "window_title" not in prompt
    assert "raw_browser_url" not in prompt
    assert "service_role" not in prompt
```

- [ ] **Step 2: Run AI tests before the gateway exists**

Run: `cd server && poetry run pytest tests/test_ai_gateway.py -q`

Expected: FAIL because the redaction boundary, provider interface, and policy service are missing.

- [ ] **Step 3: Implement provider isolation and structured validation**

Use a provider interface so the configured remote model can later be replaced by a local model without changing the domain layer. Reject malformed JSON, unknown recommendation actions, schedule overlaps, changes to locked blocks, and any attempt to set L2/L3 authority from model output. Do not persist raw prompts or raw responses.

- [ ] **Step 4: Verify L1, L2, and L3 authorization boundaries**

Run server and client tests. Confirm L1 renders a suggestion only, L2 requires a user confirmation event before persistence, and L3 is rejected unless the account has 14 consecutive days of valid records plus a fresh authorization timestamp. Add a test that AI can never call a repository write method directly.

- [ ] **Step 5: Commit the AI recommendation flow**

```bash
git add server/app/ai server/tests apps/client/lib/features/ai apps/client/test/features/ai
git commit -m "feat: add privacy-bounded AI recommendations"
```

### Task 12: Deploy with Docker, Caddy, Cloudflare, and encrypted backups

**Files:**
- Create: `infra/docker-compose.yml`
- Create: `infra/Caddyfile`
- Create: `infra/backup/backup.sh`
- Create: `infra/backup/restore-check.sh`
- Create: `infra/healthcheck.sh`
- Create: `infra/README.md`
- Modify: `infra/.env.example`
- Create: `tests/integration/test_deployed_health.py`

**Interfaces:**
- `infra/docker-compose.yml` runs `api` and `caddy` on a private Docker network; only Caddy publishes ports 80 and 443.
- Caddy reads `STUDYFLOW_API_HOST` and reverse proxies that host to `api:8000`.
- `GET https://$STUDYFLOW_API_HOST/health/live` is public; `GET /health/ready` reports the Supabase connection.
- `backup.sh` writes an encrypted `pg_dump` artifact whose filename contains UTC date and SHA-256 digest; it never prints database credentials.
- `tests/integration/test_deployed_health.py` parses `infra/docker-compose.yml` with a YAML fixture named `compose`; it does not start containers.

- [ ] **Step 1: Write deployment configuration tests**

```python
def test_compose_does_not_publish_fastapi_directly(compose):
    assert compose.services["api"].ports == []
    assert "8000" in compose.services["api"].expose
    assert set(compose.services["caddy"].ports) == {"80:80", "443:443"}
```

- [ ] **Step 2: Run configuration tests before deployment files exist**

Run: `pytest tests/integration/test_deployed_health.py -q`

Expected: FAIL because Compose, Caddy, backup, and health-check files are missing.

- [ ] **Step 3: Implement Compose and Caddy**

Use a private `studyflow` network. The API container runs Uvicorn on `0.0.0.0:8000` inside the network; Compose does not publish 8000. `infra/Caddyfile` uses `{$STUDYFLOW_API_HOST}` as the site address and `reverse_proxy api:8000`. Set Cloudflare DNS `A api` to the VPS IP with proxy enabled and set Cloudflare SSL/TLS to `Full (strict)`; open only TCP 80, 443, and restricted SSH in the VPS firewall.

- [ ] **Step 4: Verify TLS, readiness, backup, and restore**

Run on Debian 12: `docker compose --env-file .env config`, `docker compose up -d`, `curl -fsS https://$STUDYFLOW_API_HOST/health/live`, and `curl -fsS https://$STUDYFLOW_API_HOST/health/ready`. Run `backup.sh` against the real Supabase project, decrypt the artifact in a temporary directory, restore it to a temporary PostgreSQL target, and run `restore-check.sh`. Confirm Caddy logs contain no access-token or database-password values.

- [ ] **Step 5: Commit deployment assets**

```bash
git add infra tests/integration
git commit -m "ops: add Docker Caddy and encrypted backup deployment"
```

### Task 13: Run the cross-device acceptance matrix and document known limits

**Files:**
- Create: `tests/device/android-originos6-matrix.md`
- Create: `tests/device/macos-matrix.md`
- Create: `tests/integration/test_end_to_end_sync.py`
- Modify: `README.md`
- Modify: `infra/README.md`

**Interfaces:**
- The acceptance scripts exercise the public API and local clients without exposing secrets.
- The documented MVP supports offline task creation, focus recording, encrypted synchronization, conflict visibility, L1 AI suggestions, and user-confirmed L2 changes.
- `tests/integration/test_end_to_end_sync.py` defines the `two_devices` fixture as two isolated local client stores sharing a fake API backed by the real sync service; it does not require a physical device.

- [ ] **Step 1: Write the end-to-end acceptance tests**

```python
async def test_android_created_task_reaches_macos_after_reconnect(two_devices):
    task_id = await two_devices.android.create_task_offline("Read chapter 1")
    await two_devices.android.reconnect_and_sync()
    await two_devices.macos.sync()

    assert await two_devices.macos.has_task(task_id)
```

- [ ] **Step 2: Run the end-to-end suite against a disposable environment**

Run: `pytest tests/integration/test_end_to_end_sync.py -q`

Expected: the test fails until the deployed API, authenticated devices, and client test harness are configured.

- [ ] **Step 3: Execute the real device matrix**

On iQOO Z9 Turbo V2352A verify offline creation, screen lock, app cleanup, reboot, battery optimization, notification permission, exact alarm permission, usage-access permission state, clock changes, network loss/recovery, and revoked permissions. On macOS verify notification authorization, sleep/wake, menu-bar status, network loss/recovery, and app relaunch.

- [ ] **Step 4: Record failures as capability results, not silent skips**

Update the matrix with device OS/build, permission state, expected result, observed result, and a reproducible log location. Unsupported restriction or UsageStats behavior must be shown in the app as `unsupported` or `permission_missing`.

- [ ] **Step 5: Run the final verification set and commit the acceptance record**

Run: `cd server && poetry run pytest`

Run: `flutter test apps/client/test packages/domain/test packages/sync_contract/test`

Run: `git diff --check`

```bash
git add README.md tests/device tests/integration
git commit -m "test: document StudyFlow MVP acceptance matrix"
```

## Spec Coverage Check

- Product loop and offline-first behavior: Tasks 4, 6, 7, and 8.
- Supabase schema, pooler, RLS, migration, and backup recovery: Tasks 2 and 12.
- Record-level encryption, device keys, pairing, and recovery: Tasks 4 and 9.
- Sync protocol, conflicts, idempotency, and tombstones: Tasks 3, 5, and 7.
- AI privacy boundary and L0-L3 authorization: Tasks 10 and 11.
- Age/time-zone sleep adjustment rules: Task 10.
- Android OriginOS 6 and macOS adapters: Task 8 and Task 13.
- Windows/Linux/iOS compatibility space: Task 8's capability contract; platform-specific implementations remain follow-up tasks after MVP acceptance.
- Caddy, Cloudflare, Docker, Debian 12, and Supabase deployment: Task 12.
- Mature-project borrowing and license boundaries: recorded in the existing design document and referenced by the README task in Task 13.

## Execution Order

Tasks 1–5 establish the API, database, encryption contract, and synchronization path. Tasks 6–8 establish the offline client loop. Tasks 9–11 add secure enrollment, deterministic schedule policy, and AI suggestions. Task 12 deploys the service, and Task 13 verifies the complete Android/macOS flow.

The first implementation checkpoint is after Task 8: a user can create and complete work offline on Android and macOS, then synchronize encrypted records through the VPS. Device restrictions, UsageStats aggregation, Windows/Linux/iOS adapters, and CalDAV remain separate follow-up plans after this checkpoint passes.
