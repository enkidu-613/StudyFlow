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
    assert compose["services"]["api"]["ports"] == []
    assert "8000" in compose["services"]["api"]["expose"]
    assert set(compose["services"]["caddy"]["ports"]) == {"80:80", "443:443"}


def test_compose_api_and_caddy_share_private_network(compose: dict) -> None:
    api_networks = compose["services"]["api"]["networks"]
    caddy_networks = compose["services"]["caddy"]["networks"]
    assert api_networks == ["studyflow"]
    assert caddy_networks == ["studyflow"]


def test_compose_api_has_required_environment(compose: dict) -> None:
    environment = compose["services"]["api"]["environment"]
    assert "STUDYFLOW_DATABASE_URL" in environment
    assert "STUDYFLOW_BOOTSTRAP_TOKEN" in environment
    assert "STUDYFLOW_TOKEN_SIGNING_KEY" in environment


def test_caddy_reverse_proxies_api_host_to_api_container(
    caddyfile: str,
) -> None:
    assert "{$STUDYFLOW_API_HOST}" in caddyfile
    assert "reverse_proxy api:8000" in caddyfile


def test_env_example_contains_deployment_variables() -> None:
    content = (INFRA_ROOT / ".env.example").read_text(encoding="utf-8")
    assert "STUDYFLOW_API_HOST=" in content
    assert "STUDYFLOW_BACKUP_PASSPHRASE=" in content
    assert "STUDYFLOW_BACKUP_DIR=" in content


def test_backup_script_never_prints_credentials() -> None:
    script = (INFRA_ROOT / "backup" / "backup.sh").read_text(encoding="utf-8")
    assert "DATABASE_URL" in script  # reads the URL from the environment
    # The script may echo fixed strings like "Backup written", but must never
    # print the URL, the passphrase, or the openssl key material.
    assert 'echo "$DATABASE_URL"' not in script
    assert 'echo "$PASSPHRASE"' not in script
    assert 'echo "$nonce"' not in script
