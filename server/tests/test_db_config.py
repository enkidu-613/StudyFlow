import pytest
from sqlalchemy import text

from server.app.db.config import load_database_settings, normalize_database_url
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


@pytest.mark.parametrize(
    "runtime_role",
    ["postgres", "anon", "authenticated", "service_role"],
)
def test_create_engine_rejects_privileged_or_data_api_runtime_roles(
    runtime_role: str,
) -> None:
    with pytest.raises(
        DatabaseConfigurationError,
        match="dedicated application role",
    ):
        create_engine_from_env(
            f"postgresql://{runtime_role}:password@db.example.test:5432/studyflow",
        )


def test_create_engine_rejects_supabase_pooler_urls() -> None:
    with pytest.raises(
        DatabaseConfigurationError,
        match="Supabase URLs are no longer supported",
    ):
        create_engine_from_env(
            "postgresql://studyflow_server.project-ref:password"
            "@aws-0-us-east-1.pooler.supabase.com:5432/postgres",
        )


def test_load_database_settings_accepts_local_postgres() -> None:
    settings = load_database_settings(
        "postgresql://studyflow:password@postgres:5432/studyflow",
    )

    assert settings.url == (
        "postgresql+asyncpg://studyflow:password@postgres:5432/studyflow"
    )


def test_load_database_settings_translates_postgres_sslmode_for_asyncpg() -> None:
    settings = load_database_settings(
        "postgresql://studyflow:password@db.example.test:5432/studyflow?sslmode=require",
    )

    assert "ssl=require" in settings.url
    assert "sslmode" not in settings.url


def test_load_database_settings_preserves_direct_postgres_connectivity() -> None:
    settings = load_database_settings(
        "postgresql://studyflow:password@db.example.test:5432/studyflow",
    )

    assert settings.url == (
        "postgresql+asyncpg://studyflow:password@db.example.test:5432/studyflow"
    )


@pytest.mark.anyio
@pytest.mark.integration
async def test_async_engine_connects_and_disposes_with_test_database_url(
    test_database_url: str,
) -> None:
    engine = create_engine_from_env(test_database_url)

    try:
        async with engine.connect() as connection:
            result = await connection.execute(text("SELECT 1"))

        assert result.scalar_one() == 1
    finally:
        await engine.dispose()
