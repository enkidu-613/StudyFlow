from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine

from server.app.db.config import load_database_settings


class DatabaseConfigurationError(RuntimeError):
    pass


@dataclass(frozen=True, slots=True)
class DatabaseReadinessResult:
    is_ready: bool
    database: str
    message: str | None = None


class MissingDatabaseReadinessProbe:
    def __init__(self, message: str) -> None:
        self._message = message

    async def check(self) -> DatabaseReadinessResult:
        return DatabaseReadinessResult(
            is_ready=False,
            database="not_configured",
            message=self._message,
        )


class DatabaseReadinessProbe:
    def __init__(self, engine: AsyncEngine) -> None:
        self._engine = engine

    async def check(self) -> DatabaseReadinessResult:
        try:
            async with self._engine.connect() as connection:
                await connection.execute(text("SELECT 1"))
        except SQLAlchemyError as exc:
            return DatabaseReadinessResult(
                is_ready=False,
                database="error",
                message=str(exc),
            )

        return DatabaseReadinessResult(is_ready=True, database="ok")


def create_engine_from_env(database_url: str | None = None) -> AsyncEngine:
    try:
        settings = load_database_settings(database_url)
    except ValueError as exc:
        raise DatabaseConfigurationError(str(exc)) from exc

    return create_async_engine(
        settings.url,
        pool_pre_ping=True,
        pool_size=settings.pool_size,
        max_overflow=settings.max_overflow,
        pool_timeout=settings.pool_timeout_seconds,
        pool_recycle=settings.pool_recycle_seconds,
    )


def create_session_factory(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(engine, expire_on_commit=False)
