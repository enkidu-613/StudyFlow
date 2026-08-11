from __future__ import annotations

from collections.abc import AsyncIterator
from dataclasses import dataclass, field
from uuid import UUID, uuid4

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from server.app.db.context import UserContext
from server.app.db.models import Base, User
from server.app.sync.repository import SyncOperationRepository
from server.app.sync.schemas import SyncOperationV2
from server.app.sync.service import SyncService


@dataclass(frozen=True, slots=True)
class DeviceContext:
    name: str
    context: UserContext
    local_operations: list[SyncOperationV2] = field(default_factory=list)

    def create_task_offline(self, title: str) -> UUID:
        """Offline task creation: the operation is queued locally and never
        reaches the server until reconnect_and_sync."""
        record_id = uuid4()
        operation = SyncOperationV2.model_validate(
            {
                "operationId": str(uuid4()),
                "recordId": str(record_id),
                "logicalClock": len(self.local_operations) + 1,
                "entityType": "task",
                "payload": {"title": title},
                "isTombstone": False,
                "schemaVersion": 1,
            }
        )
        self.local_operations.append(operation)
        return record_id

    async def reconnect_and_sync(self, service: SyncService) -> None:
        """Flush queued offline operations to the server."""
        if not self.local_operations:
            return
        await service.push(self.context, self.local_operations)
        self.local_operations.clear()

    async def sync(self, service: SyncService) -> list[SyncOperationV2]:
        """Pull operations from the server (with pagination)."""
        operations: list[SyncOperationV2] = []
        after = 0
        while True:
            result = await service.pull(self.context, after=after, limit=50)
            operations.extend(item.operation for item in result.operations)
            if result.next_cursor <= after or not result.operations:
                break
            after = result.next_cursor
        return operations

    async def has_task(self, service: SyncService, task_id: UUID) -> bool:
        pulled = await self.sync(service)
        matching = [
            operation
            for operation in pulled
            if operation.record_id == task_id
        ]
        if not matching:
            return False
        # Operations arrive in server_sequence order, so the last one is the
        # newest state; a trailing tombstone means the task is deleted.
        return not matching[-1].is_tombstone


@dataclass(frozen=True, slots=True)
class TwoDevices:
    session_factory: async_sessionmaker[AsyncSession]
    service: SyncService
    android: DeviceContext
    macos: DeviceContext


@pytest.fixture
async def two_devices() -> AsyncIterator[TwoDevices]:
    """Two isolated local client stores sharing one fake API backed by the
    real sync service. No physical device is required."""
    engine = create_async_engine(
        "sqlite+aiosqlite://",
        poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    shared_user_id = uuid4()
    async with session_factory.begin() as session:
        session.add_all(
            [
                User(
                    user_id=shared_user_id,
                    email="user@example.com",
                    email_normalized="user@example.com",
                    password_hash="$argon2id$test",
                ),
            ],
        )

    android_context = UserContext(user_id=shared_user_id, email="user@example.com")
    macos_context = UserContext(user_id=shared_user_id, email="user@example.com")

    service = SyncService(SyncOperationRepository(session_factory))
    yield TwoDevices(
        session_factory=session_factory,
        service=service,
        android=DeviceContext(name="android", context=android_context),
        macos=DeviceContext(name="macos", context=macos_context),
    )
    await engine.dispose()


@pytest.mark.anyio
async def test_android_created_task_reaches_macos_after_reconnect(
    two_devices: TwoDevices,
) -> None:
    task_id = two_devices.android.create_task_offline("Read chapter 1")
    await two_devices.android.reconnect_and_sync(two_devices.service)
    await two_devices.macos.sync(two_devices.service)

    assert await two_devices.macos.has_task(two_devices.service, task_id)


@pytest.mark.anyio
async def test_offline_task_is_not_visible_before_reconnect(
    two_devices: TwoDevices,
) -> None:
    task_id = two_devices.android.create_task_offline("Private draft")

    # The other device must not see the task until the creator reconnects.
    assert not await two_devices.macos.has_task(two_devices.service, task_id)


@pytest.mark.anyio
async def test_both_offline_creations_sync_in_both_directions(
    two_devices: TwoDevices,
) -> None:
    android_task = two_devices.android.create_task_offline("Android task")
    macos_task = two_devices.macos.create_task_offline("macOS task")

    await two_devices.android.reconnect_and_sync(two_devices.service)
    await two_devices.macos.reconnect_and_sync(two_devices.service)

    assert await two_devices.android.has_task(two_devices.service, macos_task)
    assert await two_devices.macos.has_task(two_devices.service, android_task)


@pytest.mark.anyio
async def test_tombstone_hides_task_from_other_device(
    two_devices: TwoDevices,
) -> None:
    task_id = two_devices.android.create_task_offline("To delete")
    await two_devices.android.reconnect_and_sync(two_devices.service)
    await two_devices.macos.sync(two_devices.service)
    assert await two_devices.macos.has_task(two_devices.service, task_id)

    # Android deletes the task offline, then reconnects.
    tombstone = SyncOperationV2.model_validate(
        {
            "operationId": str(uuid4()),
            "recordId": str(task_id),
            "logicalClock": 2,
            "entityType": "task",
            "payload": {},
            "isTombstone": True,
            "schemaVersion": 1,
        }
    )
    two_devices.android.local_operations.append(tombstone)
    await two_devices.android.reconnect_and_sync(two_devices.service)

    assert not await two_devices.macos.has_task(two_devices.service, task_id)


@pytest.mark.anyio
async def test_push_acknowledges_accepted_and_duplicate_operations(
    two_devices: TwoDevices,
) -> None:
    task_id = two_devices.android.create_task_offline("Idempotent task")
    queued_operation = two_devices.android.local_operations[0]
    await two_devices.android.reconnect_and_sync(two_devices.service)

    # Reconnect with the same operations again: duplicates are acknowledged,
    # never re-inserted.
    result = await two_devices.service.push(
        two_devices.android.context,
        [queued_operation],
    )
    assert result.accepted == []
    assert result.duplicates == [queued_operation.operation_id]
    assert await two_devices.macos.has_task(two_devices.service, task_id)


@pytest.mark.anyio
async def test_pull_cursor_is_monotonic_across_devices(
    two_devices: TwoDevices,
) -> None:
    two_devices.android.create_task_offline("First")
    two_devices.macos.create_task_offline("Second")
    await two_devices.android.reconnect_and_sync(two_devices.service)
    await two_devices.macos.reconnect_and_sync(two_devices.service)

    first = await two_devices.service.pull(
        two_devices.macos.context, after=0, limit=1
    )
    assert len(first.operations) == 1
    assert first.next_cursor > 0

    second = await two_devices.service.pull(
        two_devices.macos.context, after=first.next_cursor, limit=50
    )
    assert len(second.operations) == 1
    assert second.next_cursor > first.next_cursor

    third = await two_devices.service.pull(
        two_devices.macos.context, after=second.next_cursor, limit=50
    )
    assert third.operations == []
    assert third.next_cursor == second.next_cursor


@pytest.mark.anyio
async def test_json_payload_is_transported_without_encryption(
    two_devices: TwoDevices,
) -> None:
    task_id = two_devices.android.create_task_offline("Plain JSON title")
    await two_devices.android.reconnect_and_sync(two_devices.service)
    pulled = await two_devices.macos.sync(two_devices.service)

    matching = [op for op in pulled if op.record_id == task_id]
    assert matching
    assert matching[-1].payload == {"title": "Plain JSON title"}
