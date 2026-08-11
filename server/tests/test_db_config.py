import pytest
from sqlalchemy import text

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
    ["postgres", "postgres.project-ref", "anon", "authenticated", "service_role"],
)
def test_create_engine_rejects_privileged_or_data_api_runtime_roles(
    runtime_role: str,
) -> None:
    with pytest.raises(
        DatabaseConfigurationError,
        match="dedicated non-BYPASSRLS application role",
    ):
        create_engine_from_env(
            f"postgresql://{runtime_role}:password@pooler.example.test:6543/postgres",
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
