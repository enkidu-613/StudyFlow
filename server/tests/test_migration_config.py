from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pytest
from alembic import command
from alembic.config import Config


SERVER_ROOT = Path(__file__).resolve().parents[1]


class _FakeAsyncConnection:
    def __init__(self) -> None:
        self.run_sync_called = False

    async def __aenter__(self) -> _FakeAsyncConnection:
        return self

    async def __aexit__(self, exc_type, exc_value, traceback) -> None:
        return None

    async def run_sync(self, callback) -> None:
        self.run_sync_called = True


class _FakeAsyncEngine:
    def __init__(self) -> None:
        self.connection = _FakeAsyncConnection()
        self.dispose_called = False

    def connect(self) -> _FakeAsyncConnection:
        return self.connection

    async def dispose(self) -> None:
        self.dispose_called = True


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


def test_alembic_online_configuration_uses_async_engine_and_run_sync() -> None:
    fake_engine = _FakeAsyncEngine()
    captured_configuration: dict[str, str] = {}

    def fake_async_engine_from_config(configuration, **kwargs):
        captured_configuration.update(configuration)
        return fake_engine

    with (
        patch(
            "sqlalchemy.ext.asyncio.async_engine_from_config",
            side_effect=fake_async_engine_from_config,
        ),
        patch(
            "sqlalchemy.engine_from_config",
            side_effect=AssertionError("synchronous Alembic engine was used"),
        ),
    ):
        command.upgrade(
            _alembic_config(
                "postgresql://studyflow_server.project-ref:password"
                "@aws-0-us-east-1.pooler.supabase.com:5432/postgres",
            ),
            "head",
        )

    assert captured_configuration["sqlalchemy.url"].startswith(
        "postgresql+asyncpg://",
    )
    assert fake_engine.connection.run_sync_called is True
    assert fake_engine.dispose_called is True
