# Client Session Auto Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep an authenticated StudyFlow client session valid without asking the user to sign in again when only the short-lived access token has expired.

**Architecture:** `SyncEngine` will accept an optional refresh callback, replace its in-memory access context after a 401 response, and retry the interrupted sync exactly once. `ClientSession` will schedule a proactive refresh before token expiry and notify `StudyFlowRoot` only when the long-lived refresh session is rejected.

**Tech Stack:** Flutter/Dart, flutter_test, HTTP auth API, existing local PostgreSQL-backed FastAPI service.

## Global Constraints

- Keep the existing email/password and local PostgreSQL account model unchanged.
- Never log, render, or commit access tokens, refresh tokens, passwords, or API keys.
- A refresh retry may run at most once for one sync attempt, preventing an authentication retry loop.
- A failed refresh token must clear local credentials and return the UI to the sign-in flow.

---

### Task 1: Recover a sync after a stale access token

**Files:**
- Modify: `apps/client/test/sync/sync_engine_test.dart`
- Modify: `apps/client/lib/sync/sync_engine.dart`

**Interfaces:**
- Consumes: `Future<AuthContext> Function()? refreshAuthContext`
- Produces: `SyncEngine.runOnce()` retries once with the refreshed context after `SyncAuthenticationFailure`.

- [x] **Step 1: Write the failing test**

Add a scripted API that rejects the original access token once and accepts the refreshed token. Assert that `runOnce()` succeeds, the refresher runs once, and the API observes the refreshed access token.

- [x] **Step 2: Run test to verify it fails**

Run: `mise exec -- flutter test test/sync/sync_engine_test.dart --plain-name 'authentication failure refreshes credentials and retries once'`

Expected: FAIL because `SyncEngine` has no refresh callback and returns an authentication failure.

- [x] **Step 3: Write minimal implementation**

Make the engine's stored auth context replaceable. On the first authentication failure, call the optional refresher, reject a response for a different account, then repeat the push/pull operation once. Map a failed refresh back to the existing authentication failure status.

- [x] **Step 4: Run test to verify it passes**

Run: `mise exec -- flutter test test/sync/sync_engine_test.dart --plain-name 'authentication failure refreshes credentials and retries once'`

Expected: PASS.

### Task 2: Renew credentials before expiry and return to sign-in only after refresh-session rejection

**Files:**
- Create: `apps/client/test/auth/client_session_test.dart`
- Modify: `apps/client/lib/auth/client_session.dart`
- Modify: `apps/client/lib/main.dart`

**Interfaces:**
- Consumes: `AuthRepository.refresh()` and the access token's `expiresIn` value.
- Produces: a scheduled proactive refresh, replacement sync credentials, and an `onSessionExpired` callback for an invalid refresh session.

- [x] **Step 1: Write failing tests**

Inject a controllable timer and a test workspace opener. Verify that a scheduled refresh replaces the sync engine credentials; verify a 401 refresh invokes `onSessionExpired` and does not keep a stale authenticated session.

- [x] **Step 2: Run tests to verify they fail**

Run: `mise exec -- flutter test test/auth/client_session_test.dart`

Expected: FAIL because no automatic session refresh exists.

- [x] **Step 3: Write minimal implementation**

Schedule one refresh one minute before expiry (or immediately for short test tokens). Cancel and reschedule after every successful refresh. On a 401 refresh response, let `AuthRepository` clear secure storage and have `StudyFlowRoot` close the active session and show the sign-in view.

- [x] **Step 4: Run tests to verify they pass**

Run: `mise exec -- flutter test test/auth/client_session_test.dart`

Expected: PASS.

### Task 3: Regression verification

**Files:**
- Verify: `apps/client/test/sync/sync_engine_test.dart`
- Verify: `apps/client/test/auth/client_session_test.dart`
- Verify: `apps/client/lib/auth/client_session.dart`
- Verify: `apps/client/lib/sync/sync_engine.dart`

- [x] **Step 1: Run focused auth and sync tests**

Run: `mise exec -- flutter test test/auth test/sync/sync_engine_test.dart`

- [x] **Step 2: Run static analysis**

Run: `mise exec -- flutter analyze`

- [x] **Step 3: Run the complete Flutter test suite**

Run: `mise exec -- flutter test`
