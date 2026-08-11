import pytest

from server.app.db.config import normalize_database_url


def test_normalize_database_url_accepts_local_postgresql_url() -> None:
    assert normalize_database_url(
        "postgresql://studyflow:secret@postgres:5432/studyflow",
    ) == "postgresql+asyncpg://studyflow:secret@postgres:5432/studyflow"


def test_normalize_database_url_accepts_postgres_scheme() -> None:
    assert normalize_database_url(
        "postgres://studyflow:secret@postgres:5432/studyflow",
    ) == "postgresql+asyncpg://studyflow:secret@postgres:5432/studyflow"


def test_normalize_database_url_preserves_existing_asyncpg_prefix() -> None:
    assert normalize_database_url(
        "postgresql+asyncpg://studyflow:secret@postgres:5432/studyflow",
    ) == "postgresql+asyncpg://studyflow:secret@postgres:5432/studyflow"


def test_normalize_database_url_rejects_sqlite_url() -> None:
    with pytest.raises(
        ValueError,
        match="SQLite and non-PostgreSQL URLs are not supported",
    ):
        normalize_database_url("sqlite+aiosqlite:///tmp/studyflow.db")


@pytest.mark.parametrize(
    "supabase_url",
    [
        "postgresql://studyflow:secret@aws-0-us-east-1.pooler.supabase.com:5432/postgres",
        "postgresql://studyflow:secret@db.xxxx.supabase.co:5432/postgres",
    ],
)
def test_normalize_database_url_rejects_supabase_pooler_hosts(
    supabase_url: str,
) -> None:
    with pytest.raises(
        ValueError,
        match="Supabase URLs are no longer supported",
    ):
        normalize_database_url(supabase_url)
