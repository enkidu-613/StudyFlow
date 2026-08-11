from __future__ import annotations

from dataclasses import dataclass
import os
from urllib.parse import unquote, urlsplit


SESSION_POOLER_PORT = 6543
FORBIDDEN_RUNTIME_DATABASE_ROLES = {
    "anon",
    "authenticated",
    "postgres",
    "service_role",
}


@dataclass(frozen=True, slots=True)
class DatabaseSettings:
    url: str
    pool_size: int = 5
    max_overflow: int = 10
    pool_timeout_seconds: int = 30
    pool_recycle_seconds: int = 1800


def normalize_database_url(raw_url: str) -> str:
    if raw_url.startswith("postgresql+asyncpg://"):
        return raw_url
    if raw_url.startswith("postgresql://"):
        return raw_url.replace("postgresql://", "postgresql+asyncpg://", 1)
    if raw_url.startswith("postgres://"):
        return raw_url.replace("postgres://", "postgresql+asyncpg://", 1)
    raise ValueError(
        "STUDYFLOW_DATABASE_URL must target Supabase PostgreSQL via the session "
        "pooler; SQLite and non-PostgreSQL URLs are not supported.",
    )


def load_database_settings(database_url: str | None = None) -> DatabaseSettings:
    raw_url = database_url or os.getenv("STUDYFLOW_DATABASE_URL")
    if not raw_url:
        raise ValueError(
            "STUDYFLOW_DATABASE_URL is not set. Configure the Supabase session "
            f"pooler URL on port {SESSION_POOLER_PORT}.",
        )

    normalized_url = normalize_database_url(raw_url)
    username = urlsplit(normalized_url).username
    role_name = unquote(username).split(".", 1)[0].casefold() if username else ""
    if not role_name or role_name in FORBIDDEN_RUNTIME_DATABASE_ROLES:
        raise ValueError(
            "STUDYFLOW_DATABASE_URL must use a dedicated non-BYPASSRLS "
            "application role, not postgres or a Supabase Data API role.",
        )
    return DatabaseSettings(url=normalized_url)
