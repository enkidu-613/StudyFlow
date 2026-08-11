from __future__ import annotations

import base64
from dataclasses import dataclass
from typing import Sequence
from uuid import UUID

from server.app.db.context import AccountContext
from server.app.sync.repository import (
    DeviceAccessDeniedError,
    OperationCiphertextConflictError,
    StoredSyncOperation,
    SyncOperationRepository,
)
from server.app.sync.schemas import SyncOperationV1


@dataclass(frozen=True, slots=True)
class PushResult:
    accepted: list[UUID]
    duplicates: list[UUID]
    rejected: list[UUID]


@dataclass(frozen=True, slots=True)
class PulledOperation:
    server_sequence: int
    operation_id: UUID
    operation: SyncOperationV1


@dataclass(frozen=True, slots=True)
class PullResult:
    next_cursor: int
    operations: list[PulledOperation]


class SyncAccessDeniedError(RuntimeError):
    pass


class SyncConflictError(RuntimeError):
    def __init__(self, operation_id: UUID) -> None:
        self.operation_id = operation_id
        super().__init__("Operation ID conflicts with stored ciphertext.")


class SyncService:
    def __init__(self, repository: SyncOperationRepository) -> None:
        self._repository = repository

    async def push(
        self,
        context: AccountContext,
        operations: Sequence[SyncOperationV1],
    ) -> PushResult:
        if any(operation.device_id != context.device_id for operation in operations):
            raise SyncAccessDeniedError("Device identity is not authorized.")
        try:
            result = await self._repository.push_batch(context, operations)
        except DeviceAccessDeniedError as exc:
            raise SyncAccessDeniedError("Device identity is not authorized.") from exc
        except OperationCiphertextConflictError as exc:
            raise SyncConflictError(exc.operation_id) from exc
        return PushResult(
            accepted=result.accepted,
            duplicates=result.duplicates,
            rejected=[],
        )

    async def pull(
        self,
        context: AccountContext,
        *,
        after: int,
        limit: int,
    ) -> PullResult:
        if after < 0:
            raise ValueError("after must be nonnegative")
        if limit < 1:
            raise ValueError("limit must be positive")
        page_limit = min(limit, 200)
        try:
            stored_operations = await self._repository.pull(
                context,
                after=after,
                limit=page_limit,
            )
        except DeviceAccessDeniedError as exc:
            raise SyncAccessDeniedError("Device identity is not authorized.") from exc

        operations = [_to_pulled_operation(item) for item in stored_operations]
        next_cursor = operations[-1].server_sequence if operations else after
        return PullResult(next_cursor=next_cursor, operations=operations)


def _to_pulled_operation(stored: StoredSyncOperation) -> PulledOperation:
    operation = SyncOperationV1.model_validate(
        {
            "operationId": str(stored.operation_id),
            "recordId": str(stored.record_id),
            "deviceId": str(stored.device_id),
            "logicalClock": stored.logical_clock,
            "entityType": stored.entity_type,
            "payloadNonce": base64.b64encode(stored.payload_nonce).decode("ascii"),
            "payloadCiphertext": base64.b64encode(
                stored.payload_ciphertext,
            ).decode("ascii"),
            "isTombstone": stored.is_tombstone,
            "schemaVersion": stored.schema_version,
        },
    )
    return PulledOperation(
        server_sequence=stored.server_sequence,
        operation_id=stored.operation_id,
        operation=operation,
    )
