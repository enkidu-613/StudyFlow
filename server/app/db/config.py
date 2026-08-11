from __future__ import annotations

from dataclasses import dataclass
import os
from urllib.parse import parse_qsl, unquote, urlencode, urlsplit, urlunsplit


SESSION_POOLER_PORT = 5432
TRANSACTION_POOLER_PORT = 6543
SUPAVISOR_POOLER_HOST_SUFFIX = ".pooler.supabase.com"
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
        normalized_url = raw_url
    elif raw_url.startswith("postgresql://"):
        normalized_url = raw_url.replace("postgresql://", "postgresql+asyncpg://", 1)
    elif raw_url.startswith("postgres://"):
        normalized_url = raw_url.replace("postgres://", "postgresql+asyncpg://", 1)
    else:
        raise ValueError(
            "STUDYFLOW_DATABASE_URL must target Supabase PostgreSQL via the session "
            "pooler; SQLite and non-PostgreSQL URLs are not supported.",
        )

    parsed_url = urlsplit(normalized_url)
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
            "STUDYFLOW_DATABASE_URL is not set. Configure the Supabase session "
            f"pooler URL on port {SESSION_POOLER_PORT}.",
        )

    normalized_url = normalize_database_url(raw_url)
    parsed_url = urlsplit(normalized_url)
    _validate_supavisor_pooler_port(parsed_url.hostname, parsed_url.port)

    username = parsed_url.username
    role_name = unquote(username).split(".", 1)[0].casefold() if username else ""
    if not role_name or role_name in FORBIDDEN_RUNTIME_DATABASE_ROLES:
        raise ValueError(
            "STUDYFLOW_DATABASE_URL must use a dedicated non-BYPASSRLS "
            "application role, not postgres or a Supabase Data API role.",
        )
    return DatabaseSettings(url=normalized_url)


def _validate_supavisor_pooler_port(hostname: str | None, port: int | None) -> None:
    normalized_hostname = (hostname or "").rstrip(".").casefold()
    if not (
        normalized_hostname == SUPAVISOR_POOLER_HOST_SUFFIX.lstrip(".")
        or normalized_hostname.endswith(SUPAVISOR_POOLER_HOST_SUFFIX)
    ):
        return
    if port != SESSION_POOLER_PORT:
        raise ValueError(
            "Supavisor session pooler URLs must use port 5432; "
            f"port {port or 'default'} is not the intended session mode "
            f"(transaction mode uses port {TRANSACTION_POOLER_PORT}).",
        )
