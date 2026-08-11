from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from server.app.db.context import AccountContext
from server.app.db.models import Account, Device, SyncOperation


@dataclass(frozen=True, slots=True)
class SyncOperationPayload:
    operation_id: UUID
    record_id: UUID
    payload_nonce: bytes
    payload_ciphertext: bytes
    is_tombstone: bool = False


@dataclass(frozen=True, slots=True)
class InsertResult:
    inserted: bool
    server_sequence: int | None


class SyncOperationRepository:
    def __init__(self, session_factory: async_sessionmaker[AsyncSession]) -> None:
        self._session_factory = session_factory

    async def insert_operation(
        self,
        context: AccountContext,
        operation: SyncOperationPayload,
    ) -> InsertResult:
        async with self._session_factory() as session:
            async with session.begin():
                await _set_account_context(session, context)
                await _ensure_account_and_device(session, context)

                statement = (
                    insert(SyncOperation)
                    .values(
                        account_id=context.account_id,
                        device_id=context.device_id,
                        operation_id=operation.operation_id,
                        record_id=operation.record_id,
                        payload_nonce=operation.payload_nonce,
                        payload_ciphertext=operation.payload_ciphertext,
                        is_tombstone=operation.is_tombstone,
                    )
                    .on_conflict_do_nothing(
                        index_elements=["account_id", "operation_id"],
                    )
                    .returning(SyncOperation.server_sequence)
                )
                result = await session.execute(statement)
                server_sequence = result.scalar_one_or_none()

        return InsertResult(
            inserted=server_sequence is not None,
            server_sequence=server_sequence,
        )


async def _set_account_context(session: AsyncSession, context: AccountContext) -> None:
    await session.execute(text(f"SET LOCAL app.account_id = '{context.account_id}'"))


async def _ensure_account_and_device(session: AsyncSession, context: AccountContext) -> None:
    await session.execute(
        insert(Account)
        .values(account_id=context.account_id)
        .on_conflict_do_nothing(index_elements=["account_id"]),
    )
    await session.execute(
        insert(Device)
        .values(device_id=context.device_id, account_id=context.account_id)
        .on_conflict_do_nothing(index_elements=["device_id"]),
    )
