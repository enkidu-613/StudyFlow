from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from server.app.db.context import UserContext
from server.app.db.models import UserBackup, UserSyncOperation


@dataclass(frozen=True, slots=True)
class BackupRecord:
    backup_id: UUID
    name: str
    created_at: datetime
    size_bytes: int
    operation_count: int
    last_operation_sequence: int
    status: str
    payload: dict


class BackupLimitReachedError(RuntimeError):
    def __init__(self, max_backups: int) -> None:
        self.max_backups = max_backups
        super().__init__(f"Each account can keep at most {max_backups} backups.")


class BackupSizeLimitError(RuntimeError):
    pass


class BackupNotFoundError(RuntimeError):
    pass


class BackupRepository:
    def __init__(self, session_factory: async_sessionmaker[AsyncSession]) -> None:
        self._session_factory = session_factory

    async def count_for_user(self, user_id: UUID) -> int:
        async with self._session_factory() as session:
            count = await session.scalar(
                select(func.count())
                .select_from(UserBackup)
                .where(UserBackup.user_id == user_id),
            )
        return int(count or 0)

    async def create_snapshot(
        self,
        context: UserContext,
        *,
        name: str,
        max_backup_bytes: int,
    ) -> BackupRecord:
        async with self._session_factory() as session:
            async with session.begin():
                operations = list(
                    (
                        await session.scalars(
                            select(UserSyncOperation)
                            .where(UserSyncOperation.user_id == context.user_id)
                            .order_by(UserSyncOperation.server_sequence),
                        )
                    ).all(),
                )
                payload = {
                    "schemaVersion": 1,
                    "capturedAt": datetime.now(UTC).isoformat(),
                    "operations": [
                        {
                            "operationId": str(operation.operation_id),
                            "recordId": str(operation.record_id),
                            "logicalClock": operation.logical_clock,
                            "entityType": operation.entity_type,
                            "payload": operation.payload,
                            "isTombstone": operation.is_tombstone,
                            "schemaVersion": operation.schema_version,
                        }
                        for operation in operations
                    ],
                }
                size_bytes = len(
                    json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
                )
                if size_bytes > max_backup_bytes:
                    raise BackupSizeLimitError(
                        "备份数据量过大，暂不支持创建。"
                    )
                last_sequence = (
                    operations[-1].server_sequence if operations else 0
                )
                backup = UserBackup(
                    backup_id=uuid4(),
                    user_id=context.user_id,
                    name=name,
                    payload=payload,
                    size_bytes=size_bytes,
                    operation_count=len(operations),
                    last_operation_sequence=last_sequence,
                    status="ready",
                )
                session.add(backup)
                await session.flush()
                return BackupRecord(
                    backup_id=backup.backup_id,
                    name=backup.name,
                    created_at=backup.created_at,
                    size_bytes=backup.size_bytes,
                    operation_count=backup.operation_count,
                    last_operation_sequence=backup.last_operation_sequence,
                    status=backup.status,
                    payload=backup.payload,
                )

    async def list_for_user(self, user_id: UUID) -> list[BackupRecord]:
        async with self._session_factory() as session:
            rows = list(
                (
                    await session.scalars(
                        select(UserBackup)
                        .where(UserBackup.user_id == user_id)
                        .order_by(UserBackup.created_at.desc()),
                    )
                ).all(),
            )
        return [_to_record(row) for row in rows]

    async def rename(
        self,
        user_id: UUID,
        backup_id: UUID,
        name: str,
    ) -> BackupRecord:
        async with self._session_factory() as session:
            async with session.begin():
                row = await session.scalar(
                    select(UserBackup).where(
                        UserBackup.user_id == user_id,
                        UserBackup.backup_id == backup_id,
                    ),
                )
                if row is None:
                    raise BackupNotFoundError("Backup not found.")
                row.name = name
                await session.flush()
                return _to_record(row)

    async def delete(self, user_id: UUID, backup_id: UUID) -> None:
        async with self._session_factory() as session:
            async with session.begin():
                row = await session.scalar(
                    select(UserBackup).where(
                        UserBackup.user_id == user_id,
                        UserBackup.backup_id == backup_id,
                    ),
                )
                if row is None:
                    raise BackupNotFoundError("Backup not found.")
                await session.delete(row)


def _to_record(row: UserBackup) -> BackupRecord:
    return BackupRecord(
        backup_id=row.backup_id,
        name=row.name,
        created_at=row.created_at,
        size_bytes=row.size_bytes,
        operation_count=row.operation_count,
        last_operation_sequence=row.last_operation_sequence,
        status=row.status,
        payload=row.payload,
    )
