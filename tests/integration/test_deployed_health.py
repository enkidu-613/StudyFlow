from __future__ import annotations

from pathlib import Path

import pytest
import yaml

INFRA_ROOT = Path(__file__).resolve().parents[2] / "infra"


@pytest.fixture
def compose() -> dict:
    with (INFRA_ROOT / "docker-compose.yml").open(encoding="utf-8") as handle:
        loaded = yaml.safe_load(handle)
    assert isinstance(loaded, dict) and "services" in loaded
    return loaded


@pytest.fixture
def caddyfile() -> str:
    return (INFRA_ROOT / "Caddyfile").read_text(encoding="utf-8")


def test_compose_does_not_publish_fastapi_directly(compose: dict) -> None:
    assert compose["services"]["api"]["ports"] == ["127.0.0.1:8000:8000"]
    assert "8000" in compose["services"]["api"]["expose"]
    assert set(compose["services"]["caddy"]["ports"]) == {"80:80", "443:443"}


def test_compose_runs_local_postgres_without_public_port(compose: dict) -> None:
    assert "postgres" in compose["services"]
    assert "ports" not in compose["services"]["postgres"]
    environment = compose["services"]["postgres"]["environment"]
    assert "POSTGRES_DB" in environment
    assert "POSTGRES_USER" in environment
    assert "POSTGRES_PASSWORD" in environment
    assert "studyflow_postgres" in compose["volumes"]


def test_compose_api_depends_on_healthy_postgres(compose: dict) -> None:
    depends_on = compose["services"]["api"]["depends_on"]
    assert depends_on["postgres"]["condition"] == "service_healthy"


def test_compose_api_and_caddy_share_private_network(compose: dict) -> None:
    api_networks = compose["services"]["api"]["networks"]
    caddy_networks = compose["services"]["caddy"]["networks"]
    assert api_networks == ["studyflow"]
    assert caddy_networks == ["studyflow"]


def test_compose_api_has_required_environment(compose: dict) -> None:
    environment = compose["services"]["api"]["environment"]
    assert "STUDYFLOW_DATABASE_URL" in environment
    assert "STUDYFLOW_TOKEN_SIGNING_KEY" in environment
    assert "STUDYFLOW_BOOTSTRAP_TOKEN" not in environment


def test_caddy_reverse_proxies_api_host_to_api_container(
    caddyfile: str,
) -> None:
    assert "{$STUDYFLOW_API_HOST}" in caddyfile
    assert "reverse_proxy api:8000" in caddyfile
    assert "default_sni" not in caddyfile


def test_env_example_contains_deployment_variables() -> None:
    content = (INFRA_ROOT / ".env.example").read_text(encoding="utf-8")
    assert "STUDYFLOW_API_HOST=" in content
    assert "STUDYFLOW_BACKUP_PASSPHRASE=" in content
    assert "STUDYFLOW_BACKUP_DIR=" in content
    assert "STUDYFLOW_POSTGRES_DB=" in content
    assert "STUDYFLOW_POSTGRES_USER=" in content
    assert "STUDYFLOW_POSTGRES_PASSWORD=" in content


def test_env_example_contains_no_supabase_reference() -> None:
    content = (INFRA_ROOT / ".env.example").read_text(encoding="utf-8")
    assert "supabase" not in content.casefold()


def test_bootstrap_env_script_is_executable_and_guarded() -> None:
    script = INFRA_ROOT / "bootstrap-env.sh"
    assert script.exists()
    assert script.stat().st_mode & 0o100
    content = script.read_text(encoding="utf-8")
    assert "openssl rand -hex" in content
    assert "chmod 600" in content
    assert "Refusing to overwrite" in content
    assert 'echo "$db_password"' not in content
    assert 'echo "$token_signing_key"' not in content


def test_backup_script_never_prints_credentials() -> None:
    script = (INFRA_ROOT / "backup" / "backup.sh").read_text(encoding="utf-8")
    assert "DATABASE_URL" in script  # reads the URL from the environment
    assert 'echo "$DATABASE_URL"' not in script
    assert 'echo "$PASSPHRASE"' not in script
    assert 'pg_dump --dbname="$DATABASE_URL"' in script
    assert 'pg_dump --dbname="$OLD_DATABASE_URL"' not in script
