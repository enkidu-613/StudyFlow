from __future__ import annotations

from dataclasses import dataclass
import os
from urllib.parse import parse_qsl, unquote, urlencode, urlsplit, urlunsplit


SUPAVISOR_POOLER_HOST_SUFFIX = ".pooler.supabase.com"
SUPABASE_HOST_SUFFIX = ".supabase.co"
FORBIDDEN_DATABASE_ROLES = {
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
        normalized_url = raw_url
    elif raw_url.startswith("postgresql://"):
        normalized_url = raw_url.replace("postgresql://", "postgresql+asyncpg://", 1)
    elif raw_url.startswith("postgres://"):
        normalized_url = raw_url.replace("postgres://", "postgresql+asyncpg://", 1)
    else:
        raise ValueError(
            "STUDYFLOW_DATABASE_URL must target a PostgreSQL database; "
            "SQLite and non-PostgreSQL URLs are not supported.",
        )

    parsed_url = urlsplit(normalized_url)
    _validate_no_supabase_pooler(parsed_url.hostname)
    _validate_database_role(parsed_url.username)

    query_parameters = parse_qsl(parsed_url.query, keep_blank_values=True)
    translated_query = [
        ("ssl", value) if key == "sslmode" else (key, value)
        for key, value in query_parameters
    ]
    if translated_query == query_parameters:
        return normalized_url

    return urlunsplit(
        (
            parsed_url.scheme,
            parsed_url.netloc,
            parsed_url.path,
            urlencode(translated_query),
            parsed_url.fragment,
        ),
    )


def load_database_settings(database_url: str | None = None) -> DatabaseSettings:
    raw_url = database_url or os.getenv("STUDYFLOW_DATABASE_URL")
    if not raw_url:
        raise ValueError(
            "STUDYFLOW_DATABASE_URL is not set. Configure a local or managed "
            "PostgreSQL URL for the StudyFlow API.",
        )

    return DatabaseSettings(url=normalize_database_url(raw_url))


def _validate_no_supabase_pooler(hostname: str | None) -> None:
    normalized_hostname = (hostname or "").rstrip(".").casefold()
    if (
        normalized_hostname.endswith(SUPAVISOR_POOLER_HOST_SUFFIX)
        or normalized_hostname.endswith(SUPABASE_HOST_SUFFIX)
    ):
        raise ValueError(
            "Supabase URLs are no longer supported; run PostgreSQL "
            "locally or on a dedicated managed service.",
        )


def _validate_database_role(username: str | None) -> None:
    role_name = unquote(username).casefold() if username else ""
    if not role_name or role_name in FORBIDDEN_DATABASE_ROLES:
        raise ValueError(
            "STUDYFLOW_DATABASE_URL must use a dedicated application role, "
            "not postgres, anon, authenticated, or service_role.",
        )
