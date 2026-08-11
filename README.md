# StudyFlow

StudyFlow is a cross-platform study assistant with a FastAPI backend and
Flutter client. Android (iQOO Z9 Turbo, OriginOS 6) and macOS are the first
targets; Windows, Linux, and iOS remain possible through the platform
contracts.

## Toolchain

Install the pinned runtimes with mise:

```bash
mise install
```

Use mise to select the runtimes while Poetry remains the Python dependency
manager:

```bash
mise exec -- poetry install
mise exec -- poetry run pytest server/tests/test_health.py -q
bash tool/flutter pub get
bash tool/flutter test
```

If the system Flutter directory is protected by the local macOS environment,
set `STUDYFLOW_FLUTTER_ROOT` to a writable SDK copy. The wrapper keeps Flutter
analytics disabled and redirects `PUB_CACHE` to the ignored `.tool-cache/`
directory:

```bash
export STUDYFLOW_FLUTTER_ROOT="$PWD/.tool-cache/flutter-sdk"
bash tool/flutter --version
```

## Bootstrap

- API: `cd server && mise exec -- poetry install && mise exec -- poetry run pytest tests/test_health.py -q`
- Client: `cd apps/client && bash ../../tool/flutter pub get`

## What is implemented (MVP)

- **Offline-first client**: tasks, schedule blocks, focus sessions, and
  check-ins persist encrypted in a local Drift/SQLite store and queue
  operations for later sync.
- **Encrypted sync**: record-level client encryption; the FastAPI service
  stores only opaque ciphertext plus sync metadata in Supabase PostgreSQL.
- **Auth & pairing**: account bootstrap, device pairing codes, refresh
  tokens, recovery-key export from Settings, and recovery-key restore when a
  device loses its local account key.
- **Deterministic schedule policy**: `POST /v1/schedule/proposals/validate`
  proposes small, confirmation-gated sleep-window adjustments anchored to the
  target wake time; locked blocks and rest intervals are preserved.
- **Privacy-bounded AI gateway**: `POST /v1/ai/recommendations` accepts only
  whitelisted structured fields (redaction boundary), enforces the L0–L3
  permission ladder (L3 needs 14 consecutive valid days plus a fresh grant),
  and never writes tasks or schedule blocks.
- **Deployment assets**: `infra/` contains Docker Compose (only Caddy
  publishes 80/443), Caddyfile, and encrypted pg_dump backup/restore-check
  scripts for a Debian 12 VPS backed by Supabase.

## Tests

```bash
# Server (unit + sync + scheduler + AI gateway + deployment config)
cd server && mise exec -- poetry run pytest

# Integration (cross-device sync scenarios, no physical device needed)
mise exec -- poetry run pytest ../tests/integration/test_end_to_end_sync.py

# Client
cd apps/client && bash ../../tool/flutter test

# Real API client (API base URL is configuration, not a secret)
cd apps/client && bash ../../tool/flutter run \
  --dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com
```

Device acceptance matrices: `tests/device/android-originos6-matrix.md`
(iQOO Z9 Turbo) and `tests/device/macos-matrix.md`.

## Deployment

See `infra/README.md` for the Docker/Caddy/Cloudflare topology, firewall
rules, and encrypted backup workflow. The VPS target is a fresh Debian 12
install; the provider's Fedora 34 image is out of support and must not be
used for production.

Generate the two server-only authentication values on the VPS with
`openssl rand -hex 32` and fill them into `infra/.env` as
`STUDYFLOW_BOOTSTRAP_TOKEN` and `STUDYFLOW_TOKEN_SIGNING_KEY`. The client only
receives the public `STUDYFLOW_API_BASE_URL` through `--dart-define`.

## License boundaries

Design and plan documents record which mature open-source projects
(Super Productivity, ActivityWatch, Vikunja, Nextcloud Calendar) were studied
for product models. Their code is not vendored; CalDAV interop is deferred to
a follow-up plan.
