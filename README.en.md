# StudyFlow

**English** | [中文](README.md)

StudyFlow is a cross-platform study assistant that helps you plan your day
around a fixed sleep schedule, focus on tasks, and keep everything in sync —
even offline.

## Features

- **Offline-first**: tasks, schedule blocks, and focus records live in a local
  Drift/SQLite store and sync automatically once the network is back.
- **Schedule policy**: proposes small, confirmation-gated sleep-window
  adjustments anchored to your target wake time; locked blocks and rest
  intervals stay untouched.
- **Focus sessions**: the target duration comes from a task's estimated
  minutes; the countdown finishes the task automatically and rings an alarm.
- **Privacy-first AI settings**: each device configures its own AI base URL,
  model, and API key in Settings; keys stay on the device and never reach the
  server.
- **Secure email & password auth**: Argon2id password hashes, short-lived
  access tokens, and rotating refresh tokens.

## Platforms

| Platform | Status |
|---|---|
| Android (iQOO Z9 Turbo / OriginOS 6) | ✅ First target |
| macOS | ✅ First target |
| Windows / Linux / iOS | Possible through the platform contracts |

## Tech Stack

- Client: Flutter (Dart, Riverpod, GoRouter, Drift/SQLite)
- Backend: FastAPI (Pydantic v2, SQLAlchemy Async, PyJWT, Argon2id)
- Database: PostgreSQL 16 (JSONB)
- Deployment: Docker Compose + Caddy + Cloudflare

## Quick Start

```bash
# Install the pinned runtimes
mise install

# Backend dependencies
mise exec -- poetry install

# Client dependencies
bash tool/flutter pub get
```

## Tests

```bash
# Server (auth, sync, schedule policy, etc.)
cd server && mise exec -- poetry run pytest

# Client
cd apps/client && bash ../../tool/flutter test

# Run against a real API (the API base URL is public configuration, not a secret)
cd apps/client && bash ../../tool/flutter run \
  --dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com
```

## Structure

```
apps/client/    Flutter client (features split under features/)
server/         FastAPI backend (auth, sync, schedule policy)
infra/          Docker Compose, Caddy, Cloudflare deployment & encrypted backups
packages/       Shared domain packages (domain models, etc.)
tests/device/   Device acceptance matrices (Android / macOS)
```

## Docs

- Deployment & operations: `infra/README.md`
- Engineering guidelines (for agents and collaboration tools): `.agent/AGENTS.md`
- Acceptance matrices: `tests/device/android-originos6-matrix.md`,
  `tests/device/macos-matrix.md`

## License

Design and plan documents record which mature open-source projects
(Super Productivity, ActivityWatch, Vikunja, Nextcloud Calendar) were studied
for product models. Their code is not vendored; CalDAV interop is deferred to
a follow-up plan.
