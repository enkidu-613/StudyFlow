from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence
from uuid import UUID

from server.app.db.context import UserContext
from server.app.sync.repository import (
    OperationPayloadConflictError,
    StoredSyncOperation,
    SyncOperationRepository,
)
from server.app.sync.schemas import SyncOperationV2


@dataclass(frozen=True, slots=True)
class PushResult:
    accepted: list[UUID]
    duplicates: list[UUID]
    rejected: list[UUID]


@dataclass(frozen=True, slots=True)
class PulledOperation:
    server_sequence: int
    operation_id: UUID
    operation: SyncOperationV2


@dataclass(frozen=True, slots=True)
class PullResult:
    next_cursor: int
    operations: list[PulledOperation]


class SyncAccessDeniedError(RuntimeError):
    pass


class SyncConflictError(RuntimeError):
    def __init__(self, operation_id: UUID) -> None:
        self.operation_id = operation_id
        super().__init__("Operation ID conflicts with stored payload.")


class SyncService:
    def __init__(self, repository: SyncOperationRepository) -> None:
        self._repository = repository

    async def push(
        self,
        context: UserContext,
        operations: Sequence[SyncOperationV2],
    ) -> PushResult:
        try:
            result = await self._repository.push_batch(context, operations)
        except OperationPayloadConflictError as exc:
            raise SyncConflictError(exc.operation_id) from exc
        return PushResult(
            accepted=result.accepted,
            duplicates=result.duplicates,
            rejected=[],
        )

    async def pull(
        self,
        context: UserContext,
        *,
        after: int,
        limit: int,
    ) -> PullResult:
        if after < 0:
            raise ValueError("after must be nonnegative")
        if limit < 1:
            raise ValueError("limit must be positive")
        page_limit = min(limit, 200)
        stored_operations = await self._repository.pull(
            context,
            after=after,
            limit=page_limit,
        )

        operations = [_to_pulled_operation(item) for item in stored_operations]
        next_cursor = operations[-1].server_sequence if operations else after
        return PullResult(next_cursor=next_cursor, operations=operations)


def _to_pulled_operation(stored: StoredSyncOperation) -> PulledOperation:
    operation = SyncOperationV2.model_validate(
        {
            "operationId": str(stored.operation_id),
            "recordId": str(stored.record_id),
            "logicalClock": stored.logical_clock,
            "entityType": stored.entity_type,
            "payload": stored.payload,
            "isTombstone": stored.is_tombstone,
            "schemaVersion": stored.schema_version,
        },
    )
    return PulledOperation(
        server_sequence=stored.server_sequence,
        operation_id=stored.operation_id,
        operation=operation,
    )
