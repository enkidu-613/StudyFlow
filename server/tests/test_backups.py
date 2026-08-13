from __future__ import annotations

from collections.abc import AsyncIterator
from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from server.app.auth.password_blacklist import NoopBreachedPasswordChecker
from server.app.auth.service import AuthService, AuthSettings
from server.app.backups.repository import BackupRepository
from server.app.backups.service import BackupService, BackupSettings
from server.app.db.context import UserContext
from server.app.db.models import Base, User, UserBackup
from server.app.sync.repository import SyncOperationRepository
from server.app.sync.schemas import SyncOperationV2
from server.app.sync.service import SyncService


PASSWORD = "Correct-Horse-1"
TOKEN_SIGNING_KEY = "test-signing-key-at-least-32-bytes-long"


@dataclass
class MutableClock:
    current: datetime

    def now(self) -> datetime:
        return self.current


@dataclass(frozen=True, slots=True)
class BackupHarness:
    session_factory: async_sessionmaker[AsyncSession]
    backup_service: BackupService
    sync_service: SyncService
    user_a: UserContext
    user_b: UserContext


def make_operation(
    *,
    title: str = "Backup task",
    logical_clock: int = 1,
) -> SyncOperationV2:
    return SyncOperationV2.model_validate(
        {
            "operationId": str(uuid4()),
            "recordId": str(uuid4()),
            "logicalClock": logical_clock,
            "entityType": "task",
            "payload": {"title": title},
            "isTombstone": False,
            "schemaVersion": 1,
        }
    )


@pytest.fixture
async def harness() -> AsyncIterator[BackupHarness]:
    engine = create_async_engine(
        "sqlite+aiosqlite://",
        poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    clock = MutableClock(datetime(2026, 8, 13, 3, 0, tzinfo=UTC))
    auth_service = AuthService(
        session_factory,
        AuthSettings(token_signing_key=TOKEN_SIGNING_KEY),
        clock=clock.now,
        breached_checker=NoopBreachedPasswordChecker(),
    )
    sync_service = SyncService(SyncOperationRepository(session_factory))
    backup_service = BackupService(
        BackupRepository(session_factory),
        BackupSettings(max_backups_per_user=5),
    )

    async def _register(email: str) -> UserContext:
        request = type(
            "Req",
            (),
            {"email": email, "password": PASSWORD},
        )()
        session = await auth_service.register(request)  # type: ignore[arg-type]
        return UserContext(user_id=session.user_id, email=email)

    user_a = await _register("a@example.com")
    user_b = await _register("b@example.com")
    yield BackupHarness(
        session_factory=session_factory,
        backup_service=backup_service,
        sync_service=sync_service,
        user_a=user_a,
        user_b=user_b,
    )
    await engine.dispose()


@pytest.mark.anyio
async def test_create_backup_snapshots_operations(harness: BackupHarness) -> None:
    await harness.sync_service.push(harness.user_a, [make_operation(title="Alpha")])
    await harness.sync_service.push(
        harness.user_a,
        [make_operation(title="Beta", logical_clock=2)],
    )

    record = await harness.backup_service.create(harness.user_a, name="考前备份")

    assert record.operation_count == 2
    assert record.size_bytes > 0
    assert record.status == "ready"
    assert record.name == "考前备份"
    titles = [
        operation["payload"]["title"]
        for operation in record.payload["operations"]
    ]
    assert titles == ["Alpha", "Beta"]

    async with harness.session_factory() as session:
        row = (
            await session.execute(
                select(UserBackup).where(UserBackup.backup_id == record.backup_id),
            )
        ).scalar_one()
    assert row.operation_count == 2
    assert row.last_operation_sequence == 2


@pytest.mark.anyio
async def test_backup_limit_returns_conflict(harness: BackupHarness) -> None:
    from server.app.backups.service import BackupServiceError

    for i in range(5):
        await harness.backup_service.create(harness.user_a, name=f"备份 {i}")

    with pytest.raises(BackupServiceError) as exc_info:
        await harness.backup_service.create(harness.user_a, name="第六个")

    assert exc_info.value.status_code == 409
    assert "5" in exc_info.value.detail


@pytest.mark.anyio
async def test_backups_are_isolated_between_users(harness: BackupHarness) -> None:
    await harness.backup_service.create(harness.user_a, name="A 的备份")

    b_backups = await harness.backup_service.list(harness.user_b)

    assert b_backups == []
    assert len(await harness.backup_service.list(harness.user_a)) == 1


@pytest.mark.anyio
async def test_rename_updates_name(harness: BackupHarness) -> None:
    record = await harness.backup_service.create(harness.user_a, name="旧名字")

    renamed = await harness.backup_service.rename(
        harness.user_a,
        record.backup_id,
        "新名字",
    )

    assert renamed.name == "新名字"


@pytest.mark.anyio
async def test_rename_foreign_backup_returns_not_found(harness: BackupHarness) -> None:
    from server.app.backups.service import BackupServiceError

    record = await harness.backup_service.create(harness.user_a, name="A 的备份")

    with pytest.raises(BackupServiceError) as exc_info:
        await harness.backup_service.rename(
            harness.user_b,
            record.backup_id,
            "偷改",
        )

    assert exc_info.value.status_code == 404


@pytest.mark.anyio
async def test_delete_removes_and_is_idempotent(harness: BackupHarness) -> None:
    from server.app.backups.service import BackupServiceError

    record = await harness.backup_service.create(harness.user_a, name="待删除")

    await harness.backup_service.delete(harness.user_a, record.backup_id)

    assert await harness.backup_service.list(harness.user_a) == []
    with pytest.raises(BackupServiceError) as exc_info:
        await harness.backup_service.delete(harness.user_a, record.backup_id)
    assert exc_info.value.status_code == 404


@pytest.mark.anyio
async def test_empty_account_backup_has_zero_operations(harness: BackupHarness) -> None:
    record = await harness.backup_service.create(harness.user_b, name="空备份")

    assert record.operation_count == 0
    assert record.payload["operations"] == []


@pytest.mark.anyio
async def test_oversized_backup_is_rejected(harness: BackupHarness) -> None:
    from server.app.backups.service import BackupService, BackupServiceError

    small_service = BackupService(
        BackupRepository(harness.session_factory),
        BackupSettings(max_backup_bytes=1),
    )

    await harness.sync_service.push(
        harness.user_a,
        [make_operation(title="数据较大")],
    )

    with pytest.raises(BackupServiceError) as exc_info:
        await small_service.create(harness.user_a, name="超限")

    assert exc_info.value.status_code == 422
