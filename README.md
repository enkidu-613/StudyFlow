# StudyFlow

StudyFlow is a cross-platform study assistant with a FastAPI backend and Flutter client.

## Toolchain

Install the pinned runtimes with mise:

```bash
mise install
```

Use mise to select the runtimes while Poetry remains the Python dependency manager:

```bash
mise exec -- poetry install
mise exec -- poetry run pytest server/tests/test_health.py -q
mise exec -- flutter pub get
mise exec -- flutter test
```

## Bootstrap

- API: `cd server && mise exec -- poetry install && mise exec -- poetry run pytest tests/test_health.py -q`
- Client: `cd apps/client && mise exec -- flutter pub get`

The client reserves Android, iOS, macOS, Windows, and Linux platform targets. Platform integrations remain behind the shared adapter contracts.
