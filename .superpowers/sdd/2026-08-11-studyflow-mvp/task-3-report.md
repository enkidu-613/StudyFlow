# Task 3 Report: Versioned Encrypted Sync Contract

## Status

Implemented the versioned encrypted sync contract and shared JSON fixtures on the current `codex/studyflow-mvp` branch.

## Contract

- Added Python Pydantic v2 models for `SyncOperationV1`, push request/response, pull response, and pull query validation.
- Added Dart `SyncOperationV1` and `SyncContractException` models with matching camelCase wire names.
- Restricted `schemaVersion` to `1` and `entityType` to `task`, `schedule_block`, `focus_session`, or `check_in`.
- Validated operation, record, and device IDs as UUIDs; rejected empty IDs and negative/non-integer clocks.
- Validated canonical base64 transport values and kept nonce/ciphertext opaque; no payload decoding or plaintext task fields are present.
- Enforced a 256 KiB decoded-size limit for nonce and ciphertext payload fields.
- Rejected unknown JSON fields in Python and unknown fields in Dart.
- Added pull cursor/limit validation with `after >= 0` and `1 <= limit <= 200`.

## Fixtures and tests

- Added `tests/contract/sync_push_v1.json` and `tests/contract/sync_pull_v1.json`.
- Added Python fixture round-trip, exact wire serialization, invalid-value, oversized-payload, and unknown-field tests.
- Added Dart tests consuming the same repository fixtures.
- Added the Dart `test` development dependency required to run package tests.

## Verification

- `mise exec -- poetry --directory server run pytest tests/test_sync_schemas.py -q`: 12 passed.
- `mise exec -- poetry --directory server run pytest -q`: 18 passed, 6 skipped.
- `mise exec -- flutter test test` from `packages/sync_contract`: 3 passed.
- `mise exec -- dart analyze lib test` from `packages/sync_contract`: no issues found.
- `git diff --check`: clean.

## Scope note

This task defines and tests the contract only. It does not add sync route handlers, authentication, database persistence, encryption keys, or decryption logic.

## Concerns

- The repository root is not itself a Flutter package, so the Dart checks must run from `packages/sync_contract`.
- Integration tests remain skipped when `STUDYFLOW_TEST_DATABASE_URL` is not configured; this is unrelated to the contract tests.

## Round 1 Fix Report

### Reviewer finding 1: UUID wire normalization

Root cause: Python serializes `UUID` values canonically, but Dart retained the input spelling in its final string fields and `toJson()` output. The original fixture UUIDs were numeric-only, so the first regression assertion was corrected to use valid UUIDs containing A–F characters.

Fix: Dart now lowercases `operationId`, `recordId`, and `deviceId` in the constructor before validation and serialization. Python and Dart tests assert the same lowercase wire values for uppercase UUID input.

### Reviewer finding 2: Dart validation coverage

Added targeted Dart tests for unknown fields, invalid UUIDs, negative logical clocks, unsupported entity types, malformed base64, oversized decoded nonce/ciphertext, and invalid field types. Existing schema-version, fixture round-trip, entity allowlist, and opaque payload checks remain intact.

### Round 1 verification

- `mise exec -- poetry --directory server run pytest tests/test_sync_schemas.py -q`: 13 passed.
- `mise exec -- poetry --directory server run pytest -q`: 19 passed, 6 skipped.
- `mise exec -- flutter test test` from `packages/sync_contract`: 11 passed.
- `mise exec -- dart analyze lib test` from `packages/sync_contract`: no issues found.
- Schema v1, entity allowlist, 256 KiB decoded payload limit, opaque base64 payloads, and pull limit bounds were unchanged.
