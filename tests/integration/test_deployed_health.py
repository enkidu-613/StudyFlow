from __future__ import annotations

import os
from pathlib import Path
import shutil
import stat
import subprocess
import configparser

import pytest
import yaml

INFRA_ROOT = Path(__file__).resolve().parents[2] / "infra"
QUADLET_ROOT = INFRA_ROOT / "quadlet"


@pytest.fixture
def compose() -> dict:
    with (INFRA_ROOT / "compose.yml").open(encoding="utf-8") as handle:
        loaded = yaml.safe_load(handle)
    assert isinstance(loaded, dict) and "services" in loaded
    return loaded


def test_compose_does_not_publish_fastapi_directly(compose: dict) -> None:
    assert compose["services"]["api"]["ports"] == ["127.0.0.1:8000:8000"]
    assert "8000" in compose["services"]["api"]["expose"]
    assert "caddy" not in compose["services"]


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


def test_compose_api_uses_private_network(compose: dict) -> None:
    assert compose["services"]["api"]["networks"] == ["studyflow"]


def test_compose_api_has_required_environment(compose: dict) -> None:
    environment = compose["services"]["api"]["environment"]
    assert "STUDYFLOW_DATABASE_URL" in environment
    assert "STUDYFLOW_TOKEN_SIGNING_KEY" in environment
    assert "STUDYFLOW_BOOTSTRAP_TOKEN" not in environment


def test_env_example_contains_deployment_variables() -> None:
    content = (INFRA_ROOT / ".env.example").read_text(encoding="utf-8")
    assert "STUDYFLOW_API_HOST=" in content
    assert "STUDYFLOW_BACKUP_PASSPHRASE=" in content
    assert "STUDYFLOW_BACKUP_DIR=" in content
    assert "STUDYFLOW_POSTGRES_DB=" in content
    assert "STUDYFLOW_POSTGRES_USER=" in content
    assert "STUDYFLOW_POSTGRES_PASSWORD=" in content
    assert "POSTGRES_DB=" in content
    assert "POSTGRES_USER=" in content
    assert "POSTGRES_PASSWORD=" in content


def test_env_example_contains_no_supabase_reference() -> None:
    content = (INFRA_ROOT / ".env.example").read_text(encoding="utf-8")
    assert "supabase" not in content.casefold()


def test_quadlet_units_define_rootless_postgres_and_loopback_api() -> None:
    def read_unit(name: str) -> configparser.ConfigParser:
        parser = configparser.ConfigParser(interpolation=None)
        parser.optionxform = str
        loaded = parser.read(QUADLET_ROOT / name, encoding="utf-8")
        assert loaded == [str(QUADLET_ROOT / name)]
        return parser

    network = read_unit("studyflow.network")
    volume = read_unit("studyflow-postgres.volume")
    build = read_unit("studyflow-api.build")
    postgres = read_unit("studyflow-postgres.container")
    api = read_unit("studyflow-api.container")

    assert network["Network"]["NetworkName"] == "studyflow"
    assert volume["Volume"]["VolumeName"] == "studyflow_postgres"
    assert build["Build"]["ImageTag"] == "localhost/studyflow-api:latest"
    assert build["Build"]["File"] == "infra/api.Dockerfile"
    assert postgres["Container"]["ContainerName"] == "studyflow-postgres"
    assert postgres["Container"]["EnvironmentFile"] == "/home/studyflow/app/StudyFlow/infra/.env"
    assert "studyflow-postgres.volume:/var/lib/postgresql/data" in postgres["Container"]["Volume"]
    assert postgres["Container"]["Network"] == "studyflow.network"
    assert api["Container"]["Image"] == "studyflow-api.build"
    assert api["Container"]["ContainerName"] == "studyflow-api"
    assert api["Container"]["Network"] == "studyflow.network"
    assert api["Container"]["PublishPort"] == "127.0.0.1:8000:8000"
    assert api["Service"]["Restart"] == "always"


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


def test_backup_script_falls_back_to_postgres_container() -> None:
    script = (INFRA_ROOT / "backup" / "backup.sh").read_text(encoding="utf-8")
    assert 'podman exec "$postgres_container" pg_dump' in script
    assert "@127.0.0.1:" in script
    assert "command -v pg_dump" in script


def test_backup_uses_podman_when_host_pg_dump_is_unavailable(
    tmp_path: Path,
) -> None:
    """A missing host pg_dump must fall back to Podman's postgres container."""
    command_dir = tmp_path / "bin"
    command_dir.mkdir()
    for command in (
        "awk",
        "bash",
        "cp",
        "date",
        "grep",
        "head",
        "mkdir",
        "mktemp",
        "openssl",
        "rm",
        "sha256sum",
    ):
        executable = shutil.which(command)
        assert executable is not None, command
        (command_dir / command).symlink_to(executable)

    call_log = tmp_path / "podman-calls.log"
    podman = command_dir / "podman"
    podman.write_text(
        "#!/usr/bin/env bash\n"
        "set -euo pipefail\n"
        "printf '%s\\n' \"$*\" >> \"$PODMAN_CALL_LOG\"\n"
        "case \"${1:-}\" in\n"
        "  ps) printf '%s\\n' studyflow-postgres ;;\n"
        "  exec) printf '%s\\n' 'CREATE TABLE podman_backup_test (id integer);' ;;\n"
        "  *) exit 64 ;;\n"
        "esac\n",
        encoding="utf-8",
    )
    podman.chmod(podman.stat().st_mode | stat.S_IXUSR)

    backup_dir = tmp_path / "backups"
    passphrase = "test-backup-passphrase"
    database_url = "postgresql://studyflow:secret@postgres:5432/studyflow"
    environment = {
        "PATH": str(command_dir),
        "PODMAN_CALL_LOG": str(call_log),
        "STUDYFLOW_BACKUP_DIR": str(backup_dir),
        "STUDYFLOW_BACKUP_PASSPHRASE": passphrase,
        "STUDYFLOW_DATABASE_URL": database_url,
    }
    result = subprocess.run(
        ["bash", str(INFRA_ROOT / "backup" / "backup.sh")],
        check=False,
        capture_output=True,
        env=environment,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    artifacts = list(backup_dir.glob("studyflow-*.gpg"))
    assert len(artifacts) == 1
    assert database_url not in result.stdout
    assert passphrase not in result.stdout
    assert call_log.read_text(encoding="utf-8").splitlines() == [
        "ps --format {{.Names}}",
        "exec studyflow-postgres pg_dump --dbname=postgresql://studyflow:secret@127.0.0.1:5432/studyflow --no-owner --no-privileges",
    ]

    decrypted = subprocess.run(
        [
            "openssl",
            "enc",
            "-d",
            "-aes-256-cbc",
            "-pbkdf2",
            "-iter",
            "100000",
            "-pass",
            "env:STUDYFLOW_BACKUP_PASSPHRASE",
            "-in",
            str(artifacts[0]),
        ],
        check=False,
        capture_output=True,
        env={**os.environ, "STUDYFLOW_BACKUP_PASSPHRASE": passphrase},
        text=True,
    )
    assert decrypted.returncode == 0, decrypted.stderr
    assert decrypted.stdout == "CREATE TABLE podman_backup_test (id integer);\n"
