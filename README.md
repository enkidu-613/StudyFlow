# StudyFlow

StudyFlow is a cross-platform study assistant with a FastAPI backend and Flutter client.

## Bootstrap

- API: `cd server && poetry install && poetry run pytest tests/test_health.py -q`
- Client: `cd apps/client && flutter pub get`

The client reserves Android, iOS, macOS, Windows, and Linux platform targets. Platform integrations remain behind the shared adapter contracts.
