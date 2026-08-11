import pytest

from server.app.db.engine import DatabaseConfigurationError, create_engine_from_env


def test_create_engine_requires_database_url(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("STUDYFLOW_DATABASE_URL", raising=False)

    with pytest.raises(
        DatabaseConfigurationError,
        match="STUDYFLOW_DATABASE_URL is not set",
    ):
        create_engine_from_env()


def test_create_engine_rejects_sqlite_urls() -> None:
    with pytest.raises(
        DatabaseConfigurationError,
        match="SQLite and non-PostgreSQL URLs are not supported",
    ):
        create_engine_from_env("sqlite+aiosqlite:///tmp/studyflow.db")
