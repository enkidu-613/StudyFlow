# Task 4 Report: Client-side keys and encrypted local storage

## Status

Implemented the Task 4 scope in the `codex/studyflow-mvp` linked worktree from base commit `eb2bb7aed85e13f10bf5adcfcaaf2303bb5e7cab`.

The implementation includes account-scoped platform key storage, XChaCha20-Poly1305 payload AEAD, sqlite3mc-backed encrypted Drift storage, encrypted record tables, and an account-scoped transactional pending-operation DAO. No server/database credential handling was added.

## Security and package decisions

### Payload AEAD

- Selected and locked `cryptography` 2.9.0.
- `PayloadCipher` is fixed to `Xchacha20.poly1305Aead()`; callers cannot inject a different algorithm.
- Before changing the client lockfile, a temporary standalone Dart package compiled and ran the first BoringSSL XChaCha20-Poly1305 vector generated from libsodium. The fixed public vector is retained in `key_manager_test.dart`.
- Each encryption call uses the library-generated 24-byte nonce.
- Ciphertext storage concatenates the ciphertext and 16-byte Poly1305 tag; nonce remains a separate non-secret field matching the sync contract shape.
- Canonical JSON associated data authenticates `account_id`, `record_id`, `schema_version`, and `entity_type` in fixed field order.
- Decryption rejects malformed lengths, wrong metadata, wrong account scope, and authentication failures.

References used for the package check:

- https://pub.dev/packages/cryptography
- https://boringssl.googlesource.com/boringssl/+/refs/heads/main/crypto/cipher/test/xchacha20_poly1305_tests.txt

### Platform secure storage and key hierarchy

- Selected and locked `flutter_secure_storage` 10.3.1 behind the `SecureKeyStore` adapter.
- Secure-store names include the normalized active `account_id`; keys from two accounts cannot share a storage entry.
- Android uses the package's Android Keystore-backed RSA-OAEP/AES-GCM defaults with a StudyFlow namespace. `resetOnError` is explicitly disabled so an unwrap failure cannot silently rotate/delete the only usable key.
- Android application backup is disabled to avoid restoring encrypted preferences without their Keystore key.
- macOS uses the data-protection Keychain, `unlocked_this_device`, no synchronization, and Keychain entitlements in debug/profile and release configurations.
- Device keys are loaded or generated only when absent. Malformed existing material causes `KeyRecoveryException`; it is never silently replaced.
- Account data keys are created once during bootstrap and stored under the active account. Re-creation is rejected.
- A distinct 32-byte local database key is derived from the account data key with HKDF-SHA256 and account-specific info, avoiding payload/database key reuse.

Reference used for platform configuration:

- https://pub.dev/packages/flutter_secure_storage

### Encrypted Drift database

- The originally named SQLite3MultipleCiphers approach is viable with Flutter 3.44.9 after upgrading to `sqlite3` 3.5.1 and Drift 2.34.3.
- Used the official `sqlite3` v3 build hook with `source: sqlite3mc`; no third-party wrapper adapter was needed.
- `DatabaseOpener` remains a narrow interface taking only account scope and a database key.
- Each active account gets a separate UUID-named encrypted database file.
- The opener verifies sqlite3mc cipher support, selects ChaCha20, applies the key before any schema query, enables memory security, and probes `sqlite_master` so wrong keys fail during `AppDatabase.open`.
- Key text is never logged and the temporary key-hex closure is cleared immediately after setup.
- Missing, invalid, or wrong keys produce `DatabaseRecoveryException` with user-presentable recovery guidance and no key content.
- Tables for tasks, schedule blocks, focus sessions, and check-ins store only account/record metadata, schema version, nonce, ciphertext, and update time. The pending queue stores sync metadata, nonce, and ciphertext only.
- Account and record IDs form encrypted-record primary keys. Account and operation IDs form the queue primary key.

Reference used for the adapter decision:

- https://pub.dev/documentation/sqlite3/latest/topics/hook-topic.html
- https://utelle.github.io/SQLite3MultipleCiphers/docs/configuration/config_sql_pragmas/

### Transactional operation DAO

- `enqueue` validates the operation's account against `AppDatabase.activeAccountId` and inserts inside a Drift transaction.
- Duplicate `(account_id, operation_id)` inserts use SQLite `INSERT OR IGNORE`, preserving one durable row.
- `pending(limit)` validates a positive limit, filters by active account, orders deterministically by logical clock then operation ID, and reads inside a transaction.
- `EncryptedOperation` validates UUIDs, supported entity types, schema version, logical clock, nonce length, and ciphertext/tag length.
- Cryptographic byte buffers are copied on construction and on access so callers cannot mutate validated queue material.

## Files

Created:

- `apps/client/lib/security/key_manager.dart`
- `apps/client/lib/security/payload_cipher.dart`
- `apps/client/lib/storage/app_database.dart`
- `apps/client/lib/storage/app_database.g.dart`
- `apps/client/lib/storage/tables.dart`
- `apps/client/lib/storage/operation_dao.dart`
- `apps/client/test/security/key_manager_test.dart`
- `apps/client/test/storage/operation_dao_test.dart`

Modified:

- `apps/client/pubspec.yaml`
- `apps/client/pubspec.lock`
- Android manifest backup policy
- macOS Keychain entitlements
- Flutter-generated macOS/Linux/Windows plugin registrants for `flutter_secure_storage`

## TDD evidence

Initial focused run:

```text
mise exec -- flutter test test/security/key_manager_test.dart test/storage/operation_dao_test.dart
```

Failed as expected because `key_manager.dart`, `payload_cipher.dart`, `app_database.dart`, and `operation_dao.dart` did not exist.

During security self-review, the new queue-buffer immutability test first failed with `Expected: <0>, Actual: <99>`. After defensive-copy getters were added, the same focused test passed.

## Final verification

All commands ran from `apps/client` through mise.

```text
mise exec -- flutter test test/security/key_manager_test.dart test/storage/operation_dao_test.dart
12 tests passed

mise exec -- flutter test test/storage -r expanded
6 tests passed

mise exec -- flutter test
13 tests passed

mise exec -- flutter analyze
No issues found

mise exec -- git diff --check
No output
```

The durability test closes and reopens a real on-disk sqlite3mc database, verifies the queue survives, verifies duplicate operation IDs remain one row, and verifies the file does not have the plaintext SQLite header. Wrong and missing key paths also pass.

## Native build checks and exact limitations

macOS debug build command:

```text
mise exec -- flutter build macos --debug
Xcode failed to resolve Swift Package Manager dependencies:
xcrun: error: unable to find utility "xcodebuild", not a developer tool or in PATH
```

Android debug build command:

```text
mise exec -- flutter build apk --debug
[!] No Android SDK found. Try setting the ANDROID_HOME environment variable.
```

These are host toolchain limitations. The Dart/Flutter unit tests load the downloaded sqlite3mc macOS native asset and pass through mise, but this environment cannot compile either platform runner.

## Security self-review

- No keys, key bytes, credentials, SQL statements containing keys, or plaintext record fields are logged.
- No service-role, Supabase, or database credentials were added to Flutter.
- Secure-storage corruption and database-key failure are fail-closed and do not rotate keys.
- Active account checks exist at key, payload, database-file, and operation-DAO boundaries.
- Nonce length, tag presence, entity type, schema version, UUID shape, and logical-clock bounds are validated.
- Payload metadata is authenticated, not encrypted, matching the synchronization metadata design.
- Queue and local record schemas contain no task title, notes, check-in text, feedback, prompt, or other plaintext content columns.

## Remaining concerns

- Android Keystore and macOS Keychain behavior still require device/runner validation once Xcode and the Android SDK are available.
- Secure-store creation is serialized inside one `KeyManager`, but `flutter_secure_storage` has no atomic compare-and-set across multiple simultaneous `KeyManager` instances. Account bootstrap must remain a single-flight operation at the repository layer.
- Future schema versions must add explicit Drift migration tests and preserve the cipher/key setup order before any schema access.

## Fix round 1 (reviewer findings)

This section supersedes the original report where behavior changed, especially the previous `AppDatabase`/raw-key API and the remaining concern about multiple simultaneous `KeyManager` instances.

### 1. Account-key bootstrap single-flight

- `KeyManager.createAccountDataKey()` now uses a static account-ID-keyed in-flight map shared by every `KeyManager` instance in the application isolate.
- Concurrent callers for the same normalized account join one bootstrap future and receive the same key.
- The in-flight entry is removed on success or failure and does not retain key material after bootstrap.
- After secure-store write, bootstrap reads the value back and verifies that it exactly matches the generated key. A missing or changed value raises `KeyRecoveryException` and no unverified key is returned.
- `loadAccountDataKey()` also joins an in-progress bootstrap instead of racing its secure-store write.
- Regression tests start two independent managers concurrently, assert equal returned keys, reload the persisted key, use it for AEAD round-trip, and separately assert that a store which changes the written value fails bootstrap.

### 2. Account-bound database keys

- `KeyManager.loadDatabaseKey()` now returns an `AccountDatabaseKey`, whose constructor is private and whose normalized `accountId` is inseparable from the derived key.
- `AccountScopedStore.open()` accepts the active account and its `KeyManager`; it rejects a manager from another account before opening or creating any database file and derives the database key internally.
- The narrow `DatabaseOpener` accepts only the bound key object. `EncryptedDatabaseOpener` selects the database filename from that bound account, so an unrelated raw `SecretKey` can no longer be paired with an arbitrary active account.
- `_AccountDatabase.open()` performs a second account/key binding check before invoking the opener.
- The cross-account regression passes an account-B manager for active account A, expects `StorageAccountScopeException`, and verifies no account-A database file was created.

### 3. Private Drift database and account-scoped row access

- The generated Drift database, all five table declarations, generated table accessors, and the `OperationDao` constructor are now library-private parts of `app_database.dart`.
- Production callers receive only `AccountScopedStore`, `OperationDao` through `store.operations`, and an `EncryptedRecordRepository` bound to one of the four supported encrypted entity types.
- Task, schedule-block, focus-session, and check-in `put`/`get` paths validate the requested or record account against the database's active account. Pending-operation enqueue validates its account, while pending reads always filter the active account.
- Record repositories also reject entity/repository mismatches and persist only account/record metadata, schema version, nonce, ciphertext/tag, and update time. No plaintext content columns were added.
- A looped regression round-trips every required encrypted entity table and proves both cross-account writes and reads fail. The pending-operation cross-account write regression remains present.
- `build.yaml` uses source_gen's supported `ignore_for_file` option for private generated Drift elements, preserving a clean analyzer run without making storage internals public.

### 4. Plaintext snapshot before asynchronous key loading

- `PayloadCipher.encrypt()` copies the caller's bytes to a new `Uint8List` before awaiting `loadAccountDataKey()`.
- The delayed-provider regression mutates the caller buffer while key loading is suspended and proves decryption returns the original pre-mutation bytes.

### 5. Complete AAD authentication coverage

- Dedicated tests independently alter `account_id`, `record_id`, `schema_version`, and `entity_type`; every valid altered metadata set reaches AEAD verification and raises `SecretBoxAuthenticationError`.
- `PayloadAssociatedData` accepts positive schema versions so future-version metadata can be authenticated and rejected by AEAD rather than blocked by test construction. Persisted Task 4 record and operation schemas remain restricted to version 1.
- XChaCha20-Poly1305, the retained libsodium fixed vector, library-generated fresh 24-byte nonces, defensive ciphertext buffers, and fail-closed wrong-key behavior remain unchanged.

### Round 1 TDD evidence

The focused security RED run reproduced all behavior gaps relevant to the new tests:

```text
concurrent account key bootstrap returns one durable key
Expected returned key bytes to match; actual keys differed

schema_version is authenticated
Invalid argument: schemaVersion 2 was rejected before AEAD verification

plaintext is snapshotted before awaiting the account key
Expected: [1, 2, 3]
Actual:   [99, 2, 3]
```

The storage API RED run failed to compile because `AccountScopedStore`, `EncryptedLocalRecord`, `EncryptedEntityType`, and the private-store exception/API did not yet exist. After the account-bound façade and private Drift library were implemented, the same tests passed against real on-disk sqlite3mc storage.

### Round 1 final verification

All commands ran from `apps/client` through mise after the final code change:

```text
mise exec -- flutter test test/security/key_manager_test.dart test/storage/operation_dao_test.dart
20 tests passed

mise exec -- flutter test test/storage -r expanded
7 tests passed

mise exec -- flutter test
21 tests passed

mise exec -- flutter analyze
No issues found

mise exec -- git diff --check
No output
```

The previously recorded native build limitations are unchanged: macOS runner compilation cannot start because `xcodebuild` is unavailable from `xcrun`, and Android runner compilation cannot start because no Android SDK/`ANDROID_HOME` is installed. Dart/Flutter unit tests continue to load and exercise the sqlite3mc native asset successfully through mise.

### Round 1 security self-review

- No keys, derived key bytes, credential material, plaintext payloads, or key-bearing SQL are logged or printed.
- Extracted database-key bytes are copied for conversion and the mutable copy is zeroed immediately; the temporary hex closure is cleared after sqlite3mc setup.
- Wrong account, missing key, changed secure-store write, wrong database key, malformed encrypted buffers, and altered AAD all fail closed.
- Database creation is rejected before file access when the account and key manager differ.
- Public production APIs cannot construct the private Drift database, table companions, or `OperationDao` directly.
- No server, Supabase service-role, or database credentials were introduced into Flutter.

### Round 1 concerns

- Android Keystore and macOS Keychain integration still require native runner/device verification when their missing host toolchains become available.
- The account bootstrap single-flight covers all `KeyManager` instances in the Flutter application's Dart isolate. A future architecture that performs account bootstrap from multiple independent Dart isolates or processes would require a platform-level compare-and-set or cross-isolate coordinator.

## Fix round 2 (scoped re-review)

This section supersedes the round-1 description of the database opener and database-key API. The raw executor/key pairing is no longer public.

### 1. Raw database-opening capability is library-private

- Removed public `AccountDatabaseKey` and `KeyManager.loadDatabaseKey()` from the security API.
- Database-key derivation now occurs only inside `app_database.dart`, after `AccountScopedStore` verifies that the supplied `KeyManager.accountId` matches the normalized active account.
- The derived `_AccountDatabaseKey`, `_DatabaseOpener`, `_EncryptedDatabaseOpener`, `QueryExecutor` return path, database filename selection, and sqlite3mc setup are all library-private.
- Production `AccountScopedStore.open()` accepts only `activeAccountId` and its account-scoped `KeyManager`; it creates the private application-support opener internally and returns only `AccountScopedStore`.
- `AccountScopedStore.openForTesting()` accepts a temporary base directory but still returns only the same account-scoped façade. It is annotated `visibleForTesting` and does not expose a key, executor, Drift database, table, or arbitrary-SQL method.
- Existing on-disk durability, encrypted-header, wrong-key, missing-key, cross-account key-manager, record isolation, and operation isolation tests now enter through that façade.

The public-API regression uses analyzer 13.0.0 as a direct dev dependency. It resolves a synthetic external package import that attempts the former `AccountDatabaseKey` + `DatabaseOpener` + `EncryptedDatabaseOpener` + `loadDatabaseKey()` bypass. The test requires compile diagnostics for all four removed API names, so reintroducing the complete raw executor route makes the probe compile and fails the regression.

### Bounded static probe and exact limitation

The first probe implementations launched `dart analyze` and then `dart compile kernel` as child processes from inside `flutter test`. Both contended with the active Flutter frontend and hit Flutter test's 30-second timeout instead of producing a trustworthy compile result. One orphaned public-API analyzer process, PID 48006, continued for approximately seven minutes and was terminated externally. No child-process probe remains, and a process audit after replacement found no matching process.

The replacement uses `AnalysisContextCollection` in-process with the bundled Flutter Dart SDK path discovered from the running test executable. It performs no shell/process launch, is bounded by Flutter test's standard 30-second timeout, and completed in approximately three seconds in the final runs.

### 2. Encrypted-record timestamp precision

- `EncryptedRecordRepository.put()` now stores `updatedAt.millisecondsSinceEpoch` directly.
- `EncryptedRecordRepository.get()` passes the stored integer directly to `DateTime.fromMillisecondsSinceEpoch(..., isUtc: true)`.
- The regression writes `2026-08-11T12:34:56.789Z`, reads it through the real encrypted sqlite3mc store, and asserts both exact `DateTime` equality and millisecond value `789`.
- No plaintext columns or timestamp-content fields were added; only the integer unit of the existing encrypted-record `updated_at` metadata changed.

### Round 2 TDD evidence

Public API RED:

```text
public storage API cannot compile a raw SQL opener bypass
Expected: non-empty diagnostics
Actual: empty diagnostics
Reason: A production caller compiled a raw QueryExecutor bypass.
```

The wished-for integration API also failed to compile before implementation because `AccountScopedStore.openForTesting` did not exist.

Timestamp RED:

```text
encrypted record timestamps round trip to the millisecond
Expected: 2026-08-11 12:34:56.789Z
Actual:   2026-08-11 12:34:56.000Z
```

Both regressions passed after their minimal production changes.

### Round 2 final verification

All commands ran from `apps/client` through mise after the final code change:

```text
mise exec -- flutter test test/security/key_manager_test.dart test/storage/operation_dao_test.dart
22 tests passed

mise exec -- flutter test test/storage -r expanded
9 tests passed

mise exec -- flutter test
23 tests passed

mise exec -- flutter analyze
No issues found

mise exec -- git diff --check
No output
```

### Round 2 security self-review

- Public production imports cannot obtain a StudyFlow database key, opener, raw Drift executor, generated database, table accessor, or arbitrary-SQL method.
- The only directory-selecting test façade still enforces active-account/key-manager equality and returns only account-scoped repositories and the transactional operation DAO.
- Database-key derivation remains HKDF-SHA256 with account-specific info; XChaCha20-Poly1305, fresh nonces, fixed vector, all four AAD authentication assertions, pre-await plaintext snapshot, and key-bootstrap single-flight are unchanged.
- Wrong account, missing key, wrong key, altered AAD, changed secure-store write, and cross-account record/operation access remain fail-closed.
- No key bytes, credentials, plaintext payloads, or key-bearing SQL are printed or logged.
- Task, schedule-block, focus-session, check-in, and pending-operation schemas still contain no plaintext content columns.

### Round 2 concerns

- The prior native validation limitations remain: macOS runner compilation cannot start because `xcodebuild` is unavailable, and Android runner compilation cannot start because no Android SDK/`ANDROID_HOME` is installed.
- The application-isolate boundary for account-key bootstrap remains as documented in round 1.
- Round 2 changes the unit of existing encrypted-record `updated_at` integers from seconds to milliseconds without a schema migration. StudyFlow MVP has not released this Task 4 schema; any developer database created by the pre-round-2 seconds-based implementation should be recreated.
