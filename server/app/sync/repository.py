from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Sequence
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as postgresql_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from server.app.db.context import UserContext
from server.app.db.models import UserSyncOperation
from server.app.sync.schemas import SyncOperationV2


@dataclass(frozen=True, slots=True)
class PushBatchResult:
    accepted: list[UUID]
    duplicates: list[UUID]


@dataclass(frozen=True, slots=True)
class StoredSyncOperation:
    server_sequence: int
    operation_id: UUID
    record_id: UUID
    logical_clock: int
    entity_type: str
    payload: dict[str, object]
    is_tombstone: bool
    schema_version: int


class OperationPayloadConflictError(RuntimeError):
    def __init__(self, operation_id: UUID) -> None:
        self.operation_id = operation_id
        super().__init__(f"Operation {operation_id} conflicts with stored payload.")


class SyncOperationRepository:
    def __init__(self, session_factory: async_sessionmaker[AsyncSession]) -> None:
        self._session_factory = session_factory

    async def push_batch(
        self,
        context: UserContext,
        operations: Sequence[SyncOperationV2],
    ) -> PushBatchResult:
        accepted: list[UUID] = []
        duplicates: list[UUID] = []
        async with self._session_factory() as session:
            async with session.begin():
                for operation in operations:
                    inserted = await self._insert_operation(session, context, operation)
                    if inserted:
                        accepted.append(operation.operation_id)
                        continue

                    stored = await session.scalar(
                        select(UserSyncOperation).where(
                            UserSyncOperation.user_id == context.user_id,
                            UserSyncOperation.operation_id == operation.operation_id,
                        ),
                    )
                    if stored is None:
                        raise RuntimeError("Conflicting sync operation could not be read.")
                    if not _matches_stored_operation(stored, operation):
                        raise OperationPayloadConflictError(operation.operation_id)
                    duplicates.append(operation.operation_id)

        return PushBatchResult(accepted=accepted, duplicates=duplicates)

    async def pull(
        self,
        context: UserContext,
        *,
        after: int,
        limit: int,
    ) -> list[StoredSyncOperation]:
        async with self._session_factory() as session:
            async with session.begin():
                rows = list(
                    (
                        await session.scalars(
                            select(UserSyncOperation)
                            .where(
                                UserSyncOperation.user_id == context.user_id,
                                UserSyncOperation.server_sequence > after,
                            )
                            .order_by(UserSyncOperation.server_sequence)
                            .limit(limit),
                        )
                    ).all(),
                )
        return [
            StoredSyncOperation(
                server_sequence=row.server_sequence,
                operation_id=row.operation_id,
                record_id=row.record_id,
                logical_clock=row.logical_clock,
                entity_type=row.entity_type,
                payload=row.payload,
                is_tombstone=row.is_tombstone,
                schema_version=row.schema_version,
            )
            for row in rows
        ]

    async def _insert_operation(
        self,
        session: AsyncSession,
        context: UserContext,
        operation: SyncOperationV2,
    ) -> bool:
        values = {
            "user_id": context.user_id,
            "operation_id": operation.operation_id,
            "record_id": operation.record_id,
            "logical_clock": operation.logical_clock,
            "entity_type": operation.entity_type,
            "payload": operation.payload,
            "is_tombstone": operation.is_tombstone,
            "schema_version": operation.schema_version,
        }
        dialect_name = session.get_bind().dialect.name
        if dialect_name == "postgresql":
            statement = postgresql_insert(UserSyncOperation).values(**values)
        elif dialect_name == "sqlite":
            statement = sqlite_insert(UserSyncOperation).values(**values)
        else:
            raise RuntimeError(f"Unsupported sync database dialect: {dialect_name}")
        statement = (
            statement.on_conflict_do_nothing(
                index_elements=["user_id", "operation_id"],
            )
            .returning(UserSyncOperation.server_sequence)
        )
        return (await session.scalar(statement)) is not None


def _matches_stored_operation(
    stored: UserSyncOperation,
    candidate: SyncOperationV2,
) -> bool:
    return (
        stored.record_id == candidate.record_id
        and stored.logical_clock == candidate.logical_clock
        and stored.entity_type == candidate.entity_type
        and json.dumps(stored.payload, sort_keys=True, ensure_ascii=False)
        == json.dumps(candidate.payload, sort_keys=True, ensure_ascii=False)
        and stored.is_tombstone == candidate.is_tombstone
        and stored.schema_version == candidate.schema_version
    )
