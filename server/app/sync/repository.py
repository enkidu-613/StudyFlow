from __future__ import annotations

import hmac
from dataclasses import dataclass
from hashlib import sha256
from typing import Sequence
from uuid import UUID

from sqlalchemy import select, text
from sqlalchemy.dialects.postgresql import insert as postgresql_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from server.app.db.context import AccountContext
from server.app.db.models import Device, SyncOperation
from server.app.sync.schemas import SyncOperationV1


@dataclass(frozen=True, slots=True)
class PushBatchResult:
    accepted: list[UUID]
    duplicates: list[UUID]


@dataclass(frozen=True, slots=True)
class StoredSyncOperation:
    server_sequence: int
    operation_id: UUID
    record_id: UUID
    device_id: UUID
    logical_clock: int
    entity_type: str
    payload_nonce: bytes
    payload_ciphertext: bytes
    is_tombstone: bool
    schema_version: int


class DeviceAccessDeniedError(RuntimeError):
    pass


class OperationCiphertextConflictError(RuntimeError):
    def __init__(self, operation_id: UUID) -> None:
        self.operation_id = operation_id
        super().__init__(f"Operation {operation_id} conflicts with stored ciphertext.")


class SyncOperationRepository:
    def __init__(self, session_factory: async_sessionmaker[AsyncSession]) -> None:
        self._session_factory = session_factory

    async def push_batch(
        self,
        context: AccountContext,
        operations: Sequence[SyncOperationV1],
    ) -> PushBatchResult:
        accepted: list[UUID] = []
        duplicates: list[UUID] = []
        async with self._session_factory() as session:
            async with session.begin():
                await _set_account_context(session, context.account_id)
                await _require_active_device(session, context)
                for operation in operations:
                    inserted = await self._insert_operation(session, context, operation)
                    if inserted:
                        accepted.append(operation.operation_id)
                        continue

                    stored = await session.scalar(
                        select(SyncOperation).where(
                            SyncOperation.account_id == context.account_id,
                            SyncOperation.operation_id == operation.operation_id,
                        ),
                    )
                    if stored is None:
                        raise RuntimeError("Conflicting sync operation could not be read.")
                    if not _matches_stored_operation(stored, operation):
                        raise OperationCiphertextConflictError(operation.operation_id)
                    duplicates.append(operation.operation_id)

        return PushBatchResult(accepted=accepted, duplicates=duplicates)

    async def pull(
        self,
        context: AccountContext,
        *,
        after: int,
        limit: int,
    ) -> list[StoredSyncOperation]:
        async with self._session_factory() as session:
            async with session.begin():
                await _set_account_context(session, context.account_id)
                await _require_active_device(session, context)
                rows = list(
                    (
                        await session.scalars(
                            select(SyncOperation)
                            .where(
                                SyncOperation.account_id == context.account_id,
                                SyncOperation.server_sequence > after,
                            )
                            .order_by(SyncOperation.server_sequence)
                            .limit(limit),
                        )
                    ).all(),
                )
        return [
            StoredSyncOperation(
                server_sequence=row.server_sequence,
                operation_id=row.operation_id,
                record_id=row.record_id,
                device_id=row.device_id,
                logical_clock=row.logical_clock,
                entity_type=row.entity_type,
                payload_nonce=row.payload_nonce,
                payload_ciphertext=row.payload_ciphertext,
                is_tombstone=row.is_tombstone,
                schema_version=row.schema_version,
            )
            for row in rows
        ]

    async def _insert_operation(
        self,
        session: AsyncSession,
        context: AccountContext,
        operation: SyncOperationV1,
    ) -> bool:
        values = {
            "account_id": context.account_id,
            "device_id": operation.device_id,
            "operation_id": operation.operation_id,
            "record_id": operation.record_id,
            "logical_clock": operation.logical_clock,
            "entity_type": operation.entity_type,
            "payload_nonce": operation.payload_nonce,
            "payload_ciphertext": operation.payload_ciphertext,
            "is_tombstone": operation.is_tombstone,
            "schema_version": operation.schema_version,
        }
        dialect_name = session.get_bind().dialect.name
        if dialect_name == "postgresql":
            statement = postgresql_insert(SyncOperation).values(**values)
        elif dialect_name == "sqlite":
            statement = sqlite_insert(SyncOperation).values(**values)
        else:
            raise RuntimeError(f"Unsupported sync database dialect: {dialect_name}")
        statement = (
            statement.on_conflict_do_nothing(
                index_elements=["account_id", "operation_id"],
            )
            .returning(SyncOperation.server_sequence)
        )
        return (await session.scalar(statement)) is not None


async def _set_account_context(session: AsyncSession, account_id: UUID) -> None:
    if session.get_bind().dialect.name != "postgresql":
        return
    await session.execute(
        text("SELECT set_config('app.account_id', :account_id, true)"),
        {"account_id": str(account_id)},
    )


async def _require_active_device(
    session: AsyncSession,
    context: AccountContext,
) -> None:
    device_id = await session.scalar(
        select(Device.device_id)
        .where(
            Device.account_id == context.account_id,
            Device.device_id == context.device_id,
            Device.revoked_at.is_(None),
        )
        .with_for_update(),
    )
    if device_id is None:
        raise DeviceAccessDeniedError("Device identity is not active in this account.")


def _matches_stored_operation(
    stored: SyncOperation,
    candidate: SyncOperationV1,
) -> bool:
    stored_digest = sha256(stored.payload_ciphertext).digest()
    candidate_digest = sha256(candidate.payload_ciphertext).digest()
    ciphertext_matches = hmac.compare_digest(
        stored_digest,
        candidate_digest,
    ) and hmac.compare_digest(
        stored.payload_ciphertext,
        candidate.payload_ciphertext,
    )
    return ciphertext_matches and (
        stored.record_id == candidate.record_id
        and stored.device_id == candidate.device_id
        and stored.logical_clock == candidate.logical_clock
        and stored.entity_type == candidate.entity_type
        and hmac.compare_digest(stored.payload_nonce, candidate.payload_nonce)
        and stored.is_tombstone == candidate.is_tombstone
        and stored.schema_version == candidate.schema_version
    )
