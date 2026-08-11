#!/usr/bin/env bash
# Encrypted PostgreSQL backup for StudyFlow.
#
# Requirements:
#   - psql/pg_dump (PostgreSQL client tools)
#   - openssl (encryption)
#   - STUDYFLOW_DATABASE_URL (Supabase session pooler URL)
#   - STUDYFLOW_BACKUP_PASSPHRASE
#
# Behavior:
#   - Dumps the database schema and data into a plaintext pipe
#   - Encrypts with AES-256-CBC + PBKDF2 (salt embedded in the artifact)
#   - Writes <BACKUP_DIR>/studyflow-<UTC date>-<sha256 of ciphertext>.gpg
#   - Never prints the database URL, passphrase, or credentials
set -euo pipefail

BACKUP_DIR="${STUDYFLOW_BACKUP_DIR:-/var/backups/studyflow}"
DATABASE_URL="${STUDYFLOW_DATABASE_URL:-}"
PASSPHRASE="${STUDYFLOW_BACKUP_PASSPHRASE:-}"

if [[ -z "$PASSPHRASE" ]]; then
    echo "STUDYFLOW_BACKUP_PASSPHRASE is required." >&2
    exit 1
fi
if [[ -z "$DATABASE_URL" ]]; then
    echo "STUDYFLOW_DATABASE_URL is required." >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR"

# Dump -> encrypt (PBKDF2 salt is stored in the OpenSSL header) -> digest.
ciphertext_file="$(mktemp)"
trap 'rm -f "$ciphertext_file"' EXIT

if ! pg_dump --dbname="$DATABASE_URL" --no-owner --no-privileges \
    | openssl enc -aes-256-cbc -pbkdf2 -iter 100000 \
        -pass env:STUDYFLOW_BACKUP_PASSPHRASE \
        > "$ciphertext_file" 2>/dev/null; then
    echo "Backup dump/encryption failed." >&2
    exit 1
fi

digest="$(sha256sum "$ciphertext_file" | awk '{print $1}')"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact="$BACKUP_DIR/studyflow-$stamp-$digest.gpg"
cp "$ciphertext_file" "$artifact"

echo "Backup written: $artifact"
echo "Ciphertext SHA-256: $digest"
