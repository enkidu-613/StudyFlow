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
