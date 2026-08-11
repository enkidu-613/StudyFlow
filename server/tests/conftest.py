from __future__ import annotations

import os
from collections.abc import AsyncIterator
from pathlib import Path

import asyncpg
from alembic import command
from alembic.config import Config
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncConnection, AsyncEngine
from uuid import UUID

from server.app.db.engine import (
    DatabaseReadinessProbe,
    DatabaseReadinessResult,
    create_engine_from_env,
    create_session_factory,
)
from server.app.db.models import SyncOperation
from server.app.health.routes import get_database_readiness
from server.app.main import app


SERVER_ROOT = Path(__file__).resolve().parents[1]


class DatabaseProbe:
    def __init__(self, database_url: str, engine: AsyncEngine) -> None:
        self._database_url = database_url
        self.engine = engine
        self.readiness_probe = DatabaseReadinessProbe(engine)
        self.session_factory = create_session_factory(engine)

    async def columns(self, table_name: str) -> set[str]:
        connection = await asyncpg.connect(self._database_url)
        try:
            rows = await connection.fetch(
                """
                SELECT column_name
                FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = $1
                """,
                table_name,
            )
        finally:
            await connection.close()

        return {row["column_name"] for row in rows}

    async def visible_server_sequences(self, account_id: UUID) -> set[int]:
        async with self.session_factory() as session:
            async with session.begin():
                await session.execute(text(f"SET LOCAL app.account_id = '{account_id}'"))
                result = await session.execute(select(SyncOperation.server_sequence))

        return set(result.scalars().all())


class TransactionReadinessProbe:
    def __init__(self, connection: AsyncConnection) -> None:
        self._connection = connection

    async def check(self) -> DatabaseReadinessResult:
        await self._connection.execute(text("SELECT 1"))
        return DatabaseReadinessResult(is_ready=True, database="ok")


def _build_alembic_config(database_url: str) -> Config:
    config = Config()
    config.set_main_option("script_location", str(SERVER_ROOT / "migrations"))
    config.set_main_option("prepend_sys_path", str(SERVER_ROOT.parent))
    config.set_main_option("sqlalchemy.url", database_url)
    return config


def _require_test_database_url() -> str:
    database_url = os.getenv("STUDYFLOW_TEST_DATABASE_URL")
    if not database_url:
        pytest.skip(
            "STUDYFLOW_TEST_DATABASE_URL is not set; configure an isolated "
            "PostgreSQL database for integration tests.",
        )
    return database_url


@pytest.fixture(scope="session")
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture(scope="session")
def test_database_url() -> str:
    return _require_test_database_url()


@pytest.fixture(scope="session")
async def database() -> AsyncIterator[DatabaseProbe]:
    database_url = _require_test_database_url()
    command.upgrade(_build_alembic_config(database_url), "head")
    engine = create_engine_from_env(database_url)
    try:
        yield DatabaseProbe(database_url, engine)
    finally:
        await engine.dispose()


@pytest.fixture
async def client(database: DatabaseProbe) -> AsyncIterator[AsyncClient]:
    async with database.engine.connect() as connection:
        transaction = await connection.begin()
        app.dependency_overrides[get_database_readiness] = lambda: TransactionReadinessProbe(connection)
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://testserver") as test_client:
            yield test_client
        app.dependency_overrides.clear()
        await transaction.rollback()
