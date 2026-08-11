# StudyFlow deployment

This directory contains the self-hosted deployment assets for the StudyFlow
API on a Debian 12 VPS. The service runs behind Caddy, which terminates TLS
and proxies to the FastAPI container. PostgreSQL lives in Supabase, never on
the VPS.

## Layout

- `docker-compose.yml` — runs `api` (FastAPI) and `caddy` on a private
  `studyflow` network. Only Caddy publishes ports 80/443; the API is never
  exposed directly.
- `api.Dockerfile` — builds the FastAPI container (Poetry, Python 3.12).
- `Caddyfile` — reverse-proxies `{$STUDYFLOW_API_HOST}` to `api:8000` and
  terminates HTTPS automatically.
- `healthcheck.sh` — liveness probe used by the `api` container.
- `backup/backup.sh` — encrypted `pg_dump` artifact (AES-256-GCM) whose
  filename contains the UTC timestamp and the SHA-256 digest of the
  ciphertext. It never prints credentials.
- `backup/restore-check.sh` — decrypts, verifies the digest, and optionally
  restores into a disposable PostgreSQL target.
- `.env.example` — required environment variables. Copy to `.env` on the VPS
  with real values; never commit `.env`.

## Quick start (Debian 12)

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2
sudo usermod -aG docker studyflow

cd infra
cp .env.example .env
# Generate two independent server-only secrets; paste them into .env.
openssl rand -hex 32   # STUDYFLOW_BOOTSTRAP_TOKEN
openssl rand -hex 32   # STUDYFLOW_TOKEN_SIGNING_KEY
# Edit .env and fill every remaining placeholder before continuing.
docker compose --env-file .env config   # validate before starting
docker compose up -d
```

## Values to fill in infra/.env

- STUDYFLOW_DATABASE_URL: Supabase session pooler PostgreSQL URL on port 5432,
  with ?sslmode=require. Use a dedicated database login role, not anon,
  authenticated, service_role, or a Supabase Data API key.
- STUDYFLOW_TEST_DATABASE_URL: isolated test PostgreSQL URL only; never point
  it at the production Supabase database.
- STUDYFLOW_BOOTSTRAP_TOKEN: one-time server bootstrap secret. Enter this value
  only in the client's Initialize form; it is not a client config file value
  and must not be placed in --dart-define.
- STUDYFLOW_TOKEN_SIGNING_KEY: the second random value generated above.
- STUDYFLOW_API_HOST: the Cloudflare-proxied DNS name, for example
  api.example.com.
- STUDYFLOW_BACKUP_PASSPHRASE: a separate strong passphrase for encrypted
  backups; do not reuse either authentication secret.
- STUDYFLOW_BACKUP_DIR: normally /var/backups/studyflow.

The Flutter client needs only the public API URL:

```bash
cd apps/client
bash ../../tool/flutter run --dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com
```

There is no client-side database password, Supabase service key, bootstrap
secret, or AI provider key in this command.

## Network topology

```
Android / macOS client
        │ HTTPS
        ▼
Cloudflare DNS (proxy on, SSL/TLS = Full strict)
        │ HTTPS
        ▼
Caddy (VPS, ports 80/443 only)
        │
        ▼
api:8000 (private Docker network)
        │
        ▼
Supabase PostgreSQL (session pooler, port 5432)
```

## Firewall

Open only TCP 80, 443, and restricted SSH (22 from your IP). The API
container port 8000 must not be published to the host.

## Backups

```bash
export STUDYFLOW_BACKUP_PASSPHRASE='<strong random passphrase>'
export STUDYFLOW_DATABASE_URL='postgresql://...pooler.supabase.com:5432/postgres?sslmode=require'
sudo -E infra/backup/backup.sh
```

Copy artifacts to a separate location (off-VPS). Restore check:

```bash
infra/backup/restore-check.sh /var/backups/studyflow/studyflow-*.gpg
```

## Verification

```bash
curl -fsS https://$STUDYFLOW_API_HOST/health/live   # 200 {"status":"ok"}
curl -fsS https://$STUDYFLOW_API_HOST/health/ready  # reports Supabase connection
```

## Known production notes

- The VPS currently runs Fedora 34 in the provider's image list; this project
  targets a fresh Debian 12 install. Back up and reinstall before deploying.
- Cloudflare must be set to `Full (strict)` so the origin connection is
  verified end to end.
- Caddy log lines never contain access tokens or database passwords; do not
  add them to logging configuration.
