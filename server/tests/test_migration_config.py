from __future__ import annotations

from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config


SERVER_ROOT = Path(__file__).resolve().parents[1]


def _alembic_config(database_url: str) -> Config:
    config = Config()
    config.set_main_option("script_location", str(SERVER_ROOT / "migrations"))
    config.set_main_option("prepend_sys_path", str(SERVER_ROOT.parent))
    config.set_main_option("path_separator", "os")
    config.set_main_option("sqlalchemy.url", database_url)
    return config


def test_alembic_offline_configuration_rejects_transaction_pooler_port() -> None:
    with pytest.raises(
        RuntimeError,
        match="Supavisor session pooler.*port 5432",
    ):
        command.upgrade(
            _alembic_config(
                "postgresql://studyflow_server.project-ref:password"
                "@aws-0-us-east-1.pooler.supabase.com:6543/postgres",
            ),
            "head",
            sql=True,
        )


def test_alembic_offline_configuration_accepts_session_pooler_port(
    capsys: pytest.CaptureFixture[str],
) -> None:
    config = _alembic_config(
        "postgresql://studyflow_server.project-ref:password"
        "@aws-0-us-east-1.pooler.supabase.com:5432/postgres",
    )

    command.upgrade(config, "head", sql=True)

    assert "CREATE TABLE accounts" in capsys.readouterr().out
