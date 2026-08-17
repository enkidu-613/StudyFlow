#!/usr/bin/env bash
# Encrypted PostgreSQL backup for StudyFlow.
#
# Requirements:
#   - openssl (encryption)
#   - pg_dump (PostgreSQL client tools) on the host, or Podman with the
#     studyflow postgres container (container has pg_dump built in)
#   - STUDYFLOW_DATABASE_URL or OLD_DATABASE_URL (standard postgresql:// URL)
#   - STUDYFLOW_BACKUP_PASSPHRASE
#
# Behavior:
#   - Dumps the database schema and data into a plaintext pipe
#   - Encrypts with AES-256-CBC + PBKDF2 (salt embedded in the artifact)
#   - Writes <BACKUP_DIR>/studyflow-<UTC date>-<sha256 of ciphertext>.gpg
#   - Never prints the database URL, passphrase, or credentials
set -euo pipefail

BACKUP_DIR="${STUDYFLOW_BACKUP_DIR:-/var/backups/studyflow}"
DATABASE_URL="${OLD_DATABASE_URL:-${STUDYFLOW_DATABASE_URL:-}}"
PASSPHRASE="${STUDYFLOW_BACKUP_PASSPHRASE:-}"

if [[ -z "$PASSPHRASE" ]]; then
    echo "STUDYFLOW_BACKUP_PASSPHRASE is required." >&2
    exit 1
fi
if [[ -z "$DATABASE_URL" ]]; then
    echo "STUDYFLOW_DATABASE_URL or OLD_DATABASE_URL is required." >&2
    exit 1
fi
if [[ "$DATABASE_URL" == postgresql+asyncpg://* ]]; then
    echo "DATABASE_URL must be a standard postgresql:// URL for pg_dump; " \
        "do not use postgresql+asyncpg://." >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR"

# Prefer a host pg_dump; fall back to running pg_dump inside the Podman
# postgres container when the host lacks the client tools.
if command -v pg_dump >/dev/null 2>&1; then
    dump_command=(pg_dump --dbname="$DATABASE_URL" --no-owner --no-privileges)
else
    postgres_container="$(podman ps --format '{{.Names}}' 2>/dev/null \
        | grep -E '^infra_postgres_1$|postgres' | head -n 1 || true)"
    if [[ -z "$postgres_container" ]]; then
        echo "pg_dump not found on host and no Podman postgres container is running." >&2
        exit 1
    fi
    # Inside the container the database host resolves via 127.0.0.1.
    container_url="${DATABASE_URL/@postgres:/@127.0.0.1:}"
    dump_command=(
        podman exec "$postgres_container" pg_dump
        --dbname="$container_url" --no-owner --no-privileges
    )
fi

# Dump -> encrypt (PBKDF2 salt is stored in the OpenSSL header) -> digest.
ciphertext_file="$(mktemp)"
trap 'rm -f "$ciphertext_file"' EXIT

if ! "${dump_command[@]}" \
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
