#!/usr/bin/env bash
# Restore-check for a StudyFlow encrypted backup.
#
# Usage:
#   restore-check.sh <backup-artifact.gpg> [target-db-url]
#
# Decrypts the artifact in a temporary directory, verifies its SHA-256 digest
# against the filename, and optionally restores it into a temporary
# PostgreSQL target with ON_ERROR_STOP.
set -euo pipefail

artifact="${1:?usage: restore-check.sh <artifact.gpg> [target-db-url]}"
target_url="${2:-}"
passphrase="${STUDYFLOW_BACKUP_PASSPHRASE:-}"

if [[ -z "$passphrase" ]]; then
    echo "STUDYFLOW_BACKUP_PASSPHRASE is required." >&2
    exit 1
fi
if [[ ! -f "$artifact" ]]; then
    echo "Artifact not found: $artifact" >&2
    exit 1
fi

expected_digest="$(basename "$artifact" | sed -E 's/^studyflow-[0-9TZ]+-([0-9a-f]+)\.gpg$/\1/')"
if [[ -z "$expected_digest" ]]; then
    echo "Artifact filename does not carry a digest: $(basename "$artifact")" >&2
    exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

plaintext="$work_dir/restore.sql"

if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
    -pass env:STUDYFLOW_BACKUP_PASSPHRASE \
    -in "$artifact" -out "$plaintext" 2>/dev/null; then
    echo "Decryption failed." >&2
    exit 1
fi

actual_digest="$(sha256sum "$artifact" | awk '{print $1}')"
if [[ "$actual_digest" != "$expected_digest" ]]; then
    echo "Digest mismatch: expected $expected_digest, got $actual_digest" >&2
    exit 1
fi

if [[ -z "$target_url" ]]; then
    echo "Decryption and digest verified; SQL not applied without a target URL."
    exit 0
fi

if [[ "$target_url" == postgresql+asyncpg://* ]]; then
    echo "target-db-url must be a standard postgresql:// URL for psql; " \
        "do not use postgresql+asyncpg://." >&2
    exit 1
fi

if ! psql --dbname="$target_url" --set ON_ERROR_STOP=1 --quiet < "$plaintext" >/dev/null; then
    echo "Restore into target failed." >&2
    exit 1
fi

echo "Restore check passed into target."
