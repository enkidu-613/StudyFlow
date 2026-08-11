#!/usr/bin/env bash
# Generate the production .env for StudyFlow on the VPS.
#
# Usage:
#   ./bootstrap-env.sh api.example.com
#
# Behavior:
#   - Refuses to overwrite an existing infra/.env.
#   - Generates a random PostgreSQL password and JWT signing key.
#   - Writes a complete STUDYFLOW_DATABASE_URL with the password URL-encoded.
#   - Writes the .env with permissions 600.
#   - Never prints the database password, JWT key, or backup passphrase.
#   - If STUDYFLOW_BACKUP_PASSPHRASE is not provided, generates one and
#     prints it exactly once; the operator must store it outside the VPS.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <api-host>" >&2
    exit 1
fi

api_host="$1"
if [[ -z "$api_host" || "$api_host" == *"://"* || "$api_host" == *"/"* ]]; then
    echo "api-host must be a bare domain such as api.example.com" >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="$script_dir/.env"

if [[ -e "$env_file" ]]; then
    echo "Refusing to overwrite existing $env_file" >&2
    exit 1
fi

db_name="studyflow"
db_user="studyflow_app"
db_password="$(openssl rand -hex 24)"
token_signing_key="$(openssl rand -hex 32)"
backup_passphrase="${STUDYFLOW_BACKUP_PASSPHRASE:-}"

if [[ -z "$backup_passphrase" ]]; then
    backup_passphrase="$(openssl rand -hex 24)"
    echo "Generated backup passphrase (save it now outside the VPS, it will"
    echo "not be shown again):"
    echo "STUDYFLOW_BACKUP_PASSPHRASE=$backup_passphrase"
    echo
fi

database_url="postgresql://${db_user}:${db_password}@postgres:5432/${db_name}"

umask 177
cat > "$env_file" <<EOF
STUDYFLOW_POSTGRES_DB=${db_name}
STUDYFLOW_POSTGRES_USER=${db_user}
STUDYFLOW_POSTGRES_PASSWORD=${db_password}
STUDYFLOW_DATABASE_URL=${database_url}
STUDYFLOW_TOKEN_SIGNING_KEY=${token_signing_key}
STUDYFLOW_API_HOST=${api_host}
STUDYFLOW_BACKUP_PASSPHRASE=${backup_passphrase}
STUDYFLOW_BACKUP_DIR=/var/backups/studyflow
EOF
chmod 600 "$env_file"

echo "Wrote $env_file (permissions 600)."
