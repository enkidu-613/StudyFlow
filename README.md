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

## What is implemented

- **Offline-first client**: tasks, schedule blocks, focus sessions, and
  check-ins persist in a local Drift/SQLite store and queue operations for
  later sync.
- **Email & password auth**: `POST /v1/auth/register`, `login`, `refresh`,
  and `logout`; Argon2id password hashes, rotating refresh tokens stored as
  digests, short-lived access JWTs scoped by `user_id`.
- **User-scoped JSON sync**: `POST /v1/sync/push` and `GET /v1/sync/pull`
  store JSONB payloads keyed by the JWT `user_id`; idempotent operation IDs,
  cursor-based pull, and per-user isolation.
- **Deterministic schedule policy**: `POST /v1/schedule/proposals/validate`
  proposes small, confirmation-gated sleep-window adjustments anchored to the
  target wake time; locked blocks and rest intervals are preserved.
- **Client-side AI settings**: each device configures its own AI Base URL,
  model, and API key in Settings; keys stay in the device secure storage and
  never reach the VPS. The server has no AI routes.
- **Local PostgreSQL deployment**: `infra/` runs PostgreSQL 16, FastAPI, and
  Caddy in Docker on a Debian 12 VPS; only Caddy publishes 80/443.

## Tests

```bash
# Server (auth + sync + scheduler + database config + deployment config)
cd server && mise exec -- poetry run pytest

# Client
cd apps/client && bash ../../tool/flutter test

# Real API client (API base URL is configuration, not a secret)
cd apps/client && bash ../../tool/flutter run \
  --dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com
```

Device acceptance matrices: `tests/device/android-originos6-matrix.md`
(iQOO Z9 Turbo) and `tests/device/macos-matrix.md`.

## 部署

完整的 Debian 12、Docker、Caddy、Cloudflare、防火墙和加密备份步骤请阅读
`infra/README.md`。生产环境不要使用已经停止维护的 Fedora 34 镜像。

在 VPS 的 `infra/` 目录执行 `./bootstrap-env.sh api.example.com` 自动生成
`.env`（数据库密码、JWT 密钥、备份口令）。客户端只需要通过
`--dart-define` 接收公开的 `STUDYFLOW_API_BASE_URL`，不需要数据库密码、
JWT 密钥或 AI Key。

## License boundaries

Design and plan documents record which mature open-source projects
(Super Productivity, ActivityWatch, Vikunja, Nextcloud Calendar) were studied
for product models. Their code is not vendored; CalDAV interop is deferred to
a follow-up plan.
