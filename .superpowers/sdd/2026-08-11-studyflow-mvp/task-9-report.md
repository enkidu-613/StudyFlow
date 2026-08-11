# Task 9 Report: Authentication, Device Pairing, and Recovery

Date: 2026-08-11
Worktree: `/Users/enkidu/Documents/ChatGPT/StudyFlow/.worktrees/studyflow-mvp`
Branch: `codex/studyflow-mvp`
Base commit: `06d0e84a00b5f926610fb1665c43b04f98b900ba`

## Status

Implemented Task 9 account bootstrap, password login, access/refresh sessions,
device enrollment/pairing/revocation, client auth-context persistence, X25519
account-key envelopes, and local recovery-key export/restore screens.

No production database, Supabase, bootstrap, signing, password, token, device
private-key, account-data-key, or recovery-key value was used or printed.

## Server implementation

- Added `POST /v1/auth/bootstrap`, guarded by the server-only
  `STUDYFLOW_BOOTSTRAP_TOKEN`. A unique bootstrap-state row makes account and
  first-device creation one-time and transactionally rolls back concurrent
  losers.
- Added password login with Argon2id hashes. Argon2 work runs outside the async
  event loop, and a successful login rehashes parameters when needed.
- Added 15-minute HS256 access tokens with required issuer, audience, subject,
  `account_id` (subject), `device_id`, token type, issued-at, expiry, and JTI
  claims. Protected dependencies decode the token and then verify the exact
  `(account_id, device_id)` row is active.
- Added opaque, high-entropy rotating refresh tokens. Only domain-separated
  HMAC-SHA256 digests are stored. Rotation revokes the old row and records its
  replacement; replay returns HTTP 401.
- Added authenticated pairing-code creation and one-time pairing consumption.
  Pairing codes are exactly six digits, expire after ten minutes, are stored
  only as domain-separated HMAC-SHA256 digests, and are bound to the target
  device UUID and exact 32-byte X25519 public key.
- Pairing creates the new device under the authenticated source account and
  returns only the opaque account-data-key envelope that the existing client
  encrypted for that target public key.
- Added authenticated device revocation. The target lookup is scoped by the
  caller's `account_id`, revocation invalidates refresh sessions, and account
  rows plus opaque encrypted sync operations remain intact.
- Added migration `002_auth_devices` for password hashes, device public keys,
  encrypted account-key envelopes, revocation timestamps, bootstrap state,
  refresh sessions, pairing codes, and device RLS policies needed for
  authenticated lookup/update.
- Authentication startup reads bootstrap/signing secrets only from server
  environment variables. Missing auth secrets leave auth endpoints unavailable
  without affecting liveness/readiness initialization.

## Client implementation

- Added `AuthRepository` and `HttpAuthApi` for login, refresh, pairing-code
  creation, pairing, and revocation.
- `AuthContext` keeps `account_id`, `device_id`, access token, rotating refresh
  token, and encrypted account-data-key envelope in one validated object.
- `FlutterSecureAuthContextStore` writes that object as one secure-storage
  value. Login/pair/refresh persist the complete object before activating it;
  logout and self-revocation delete the complete active context.
- Refresh fails closed and clears the active context if a server response
  changes either the account or device identity.
- The HTTP client rejects credentials in origins, malformed origins, and
  cleartext non-loopback origins. Authentication error objects never include
  response bodies that could contain tokens.
- Added `DeviceEnrollmentCrypto` using persistent X25519 device agreement keys,
  HKDF-SHA256 domain separation, and XChaCha20-Poly1305. The account-data-key
  envelope authenticates the account ID and target device ID and opens only on
  the target device private key.
- Added local recovery export/restore to `KeyManager`. The recovery payload is
  account-bound, versioned, validated, and handled only by client code; no auth
  transport accepts a recovery-key parameter.
- Added a six-digit enrollment screen with explicit expired/failed retry copy.
- Added a recovery screen that requires explicit confirmation before revealing
  the key, reveals it once per screen lifecycle, supports local restore, and
  states that encrypted data is non-recoverable without the correct key.

## Files changed

Created:

- `server/app/auth/__init__.py`
- `server/app/auth/models.py`
- `server/app/auth/routes.py`
- `server/app/auth/service.py`
- `server/migrations/versions/002_auth_devices.py`
- `server/tests/test_auth_and_pairing.py`
- `apps/client/lib/auth/auth_repository.dart`
- `apps/client/lib/auth/device_enrollment_crypto.dart`
- `apps/client/lib/auth/pairing_screen.dart`
- `apps/client/lib/auth/recovery_key_screen.dart`
- `apps/client/test/auth/auth_repository_test.dart`

Modified:

- `server/app/db/models.py`
- `server/app/main.py`
- `server/pyproject.toml`
- `infra/.env.example`
- `apps/client/lib/security/key_manager.dart`
- `apps/client/pubspec.yaml`
- `apps/client/pubspec.lock`

`server/poetry.lock` was refreshed locally by Poetry but remains ignored by the
repository's existing `poetry.lock` policy, so it is not part of the commit.

## TDD evidence

Server RED:

```text
mise exec -- poetry --directory server run pytest tests/test_auth_and_pairing.py -q
ModuleNotFoundError: No module named 'server.app.auth'
```

Server security regressions were also observed failing before their fixes:

```text
valid access tokens rejected because PyJWT used the host clock instead of the injected clock
non-X25519 public key expected HTTP 422, received HTTP 201
```

Server focused GREEN:

```text
mise exec -- poetry --directory server run pytest tests/test_auth_and_pairing.py -q
9 passed in 0.48s
```

Client RED:

```text
mise exec -- flutter test test/auth/auth_repository_test.dart
Error when reading lib/auth/auth_repository.dart: No such file or directory
Error when reading lib/auth/device_enrollment_crypto.dart: No such file or directory
```

The cleartext-origin security regression first failed because
`HttpAuthApi(http://api.example.test)` was accepted. It passed after restricting
HTTP to loopback origins.

Client focused GREEN:

```text
mise exec -- flutter test test/auth/auth_repository_test.dart
11 tests passed
```

## Final verification

All commands used the repository's mise-managed Python or Flutter toolchain.

```text
mise exec -- poetry --directory server run pytest -q
28 passed, 6 skipped in 0.63s

mise exec -- flutter test
34 tests passed

mise exec -- flutter analyze
No issues found! (ran in 4.8s)

mise exec -- poetry --directory server check
Exit 0; only pre-existing Poetry metadata deprecation warnings

mise exec -- poetry --directory server run alembic heads
002_auth_devices (head)

git diff --check
No output
```

The six skipped tests are the existing PostgreSQL migration/RLS integration
tests. `STUDYFLOW_TEST_DATABASE_URL` is not configured in this environment, so
the tests correctly did not contact any Supabase or production database.

Native runner builds were not attempted: `xcodebuild` is unavailable through
`xcrun`, and neither `ANDROID_HOME` nor `ANDROID_SDK_ROOT` is configured. The
pure Dart cryptography, repository, secure-store adapter boundary, and widget
tests all ran successfully.

## Security self-review

- `account_id` is the top-level owner in every account/device/session/pairing
  persistence row and every auth response.
- Every access token carries account and device identity; every protected
  device operation rechecks the exact active ownership row.
- Account A receives HTTP 409/404/401 when attempting to pair, revoke, or use
  account B's device, without changing account B's row.
- Bootstrap and signing secrets exist only in server environment loading and
  placeholder deployment documentation; neither is present in Flutter code.
- Passwords are represented as Pydantic `SecretStr` at the route boundary and
  stored only as Argon2id hashes.
- Refresh tokens and pairing codes are never stored raw. Pairing and refresh
  digests are domain-separated.
- The server receives device public keys and opaque encrypted account-key
  envelopes, never account-data keys, device private keys, or recovery keys.
- The client stores active identity/tokens/envelope as one secure-storage value
  and clears that value on logout or active-device revocation.
- Recovery material is absent from `AuthContext`, `AuthApi`, and every HTTP
  payload. Recovery text exists only in the explicitly confirmed recovery
  screen lifecycle and secure key storage.
- No implementation logging or debug printing was added.

## Concerns and follow-up

- PostgreSQL migration and RLS behavior still needs execution against an
  isolated PostgreSQL database before deployment; the current environment had
  no `STUDYFLOW_TEST_DATABASE_URL`.
- Six-digit pairing codes have a ten-minute lifetime and one-time consumption,
  but deployment must add per-source/IP rate limiting at the FastAPI/Caddy
  boundary before exposing the endpoint publicly.
- Android Keystore and macOS Keychain behavior still requires native runner
  validation when the Android SDK and full Xcode toolchain are available.
