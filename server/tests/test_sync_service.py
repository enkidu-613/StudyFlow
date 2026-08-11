from __future__ import annotations

import base64
from collections.abc import AsyncIterator
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from server.app.auth.service import AuthService, AuthSettings
from server.app.db.context import AccountContext
from server.app.db.models import Account, Base, Device, SyncOperation
from server.app.sync.repository import SyncOperationRepository
from server.app.sync.routes import router as sync_router
from server.app.sync.schemas import SyncOperationV1
from server.app.sync.service import (
    SyncAccessDeniedError,
    SyncConflictError,
    SyncService,
)


TOKEN_SIGNING_KEY = "test-sync-signing-key-at-least-32-bytes"


@dataclass(frozen=True, slots=True)
class SyncHarness:
    session_factory: async_sessionmaker[AsyncSession]
    service: SyncService
    first_context: AccountContext
    second_context: AccountContext

    async def count(self, account_id: UUID) -> int:
        async with self.session_factory() as session:
            count = await session.scalar(
                select(func.count())
                .select_from(SyncOperation)
                .where(SyncOperation.account_id == account_id),
            )
        return int(count or 0)


@pytest.fixture
async def sync_harness() -> AsyncIterator[SyncHarness]:
    engine = create_async_engine(
        "sqlite+aiosqlite://",
        poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    first_context = AccountContext(account_id=uuid4(), device_id=uuid4())
    second_context = AccountContext(account_id=uuid4(), device_id=uuid4())
    async with session_factory.begin() as session:
        session.add_all(
            [
                Account(account_id=first_context.account_id),
                Account(account_id=second_context.account_id),
                Device(
                    account_id=first_context.account_id,
                    device_id=first_context.device_id,
                ),
                Device(
                    account_id=second_context.account_id,
                    device_id=second_context.device_id,
                ),
            ],
        )

    repository = SyncOperationRepository(session_factory)
    yield SyncHarness(
        session_factory=session_factory,
        service=SyncService(repository),
        first_context=first_context,
        second_context=second_context,
    )
    await engine.dispose()


def make_operation(
    context: AccountContext,
    *,
    operation_id: UUID | None = None,
    logical_clock: int = 1,
    ciphertext: bytes = b"opaque-ciphertext",
) -> SyncOperationV1:
    return SyncOperationV1.model_validate(
        {
            "operationId": str(operation_id or uuid4()),
            "recordId": str(uuid4()),
            "deviceId": str(context.device_id),
            "logicalClock": logical_clock,
            "entityType": "task",
            "payloadNonce": "b3BhcXVlLW5vbmNl",
            "payloadCiphertext": base64.b64encode(ciphertext).decode("ascii"),
            "isTombstone": False,
            "schemaVersion": 1,
        },
    )


@pytest.mark.anyio
async def test_push_is_idempotent_after_matching_ciphertext_digest(
    sync_harness: SyncHarness,
) -> None:
    operation = make_operation(sync_harness.first_context)

    first = await sync_harness.service.push(sync_harness.first_context, [operation])
    second = await sync_harness.service.push(sync_harness.first_context, [operation])

    assert first.accepted == [operation.operation_id]
    assert first.duplicates == []
    assert second.accepted == []
    assert second.duplicates == [operation.operation_id]
    assert await sync_harness.count(sync_harness.first_context.account_id) == 1


@pytest.mark.anyio
async def test_conflicting_operation_rolls_back_the_entire_push_batch(
    sync_harness: SyncHarness,
) -> None:
    existing = make_operation(sync_harness.first_context)
    await sync_harness.service.push(sync_harness.first_context, [existing])
    new_operation = make_operation(sync_harness.first_context, logical_clock=2)
    conflicting = existing.model_copy(
        update={"payload_ciphertext": b"different-opaque-ciphertext"},
    )

    with pytest.raises(SyncConflictError):
        await sync_harness.service.push(
            sync_harness.first_context,
            [new_operation, conflicting],
        )

    assert await sync_harness.count(sync_harness.first_context.account_id) == 1


@pytest.mark.anyio
async def test_push_rejects_an_operation_claiming_another_device(
    sync_harness: SyncHarness,
) -> None:
    operation = make_operation(sync_harness.second_context)

    with pytest.raises(SyncAccessDeniedError):
        await sync_harness.service.push(sync_harness.first_context, [operation])

    assert await sync_harness.count(sync_harness.first_context.account_id) == 0


@pytest.mark.anyio
async def test_push_rejects_a_revoked_request_device(
    sync_harness: SyncHarness,
) -> None:
    async with sync_harness.session_factory.begin() as session:
        device = await session.get(
            Device,
            {
                "account_id": sync_harness.first_context.account_id,
                "device_id": sync_harness.first_context.device_id,
            },
        )
        assert device is not None
        device.revoked_at = datetime.now(UTC)

    with pytest.raises(SyncAccessDeniedError):
        await sync_harness.service.push(
            sync_harness.first_context,
            [make_operation(sync_harness.first_context)],
        )


@pytest.mark.anyio
async def test_pull_is_account_scoped_ordered_and_advances_the_cursor(
    sync_harness: SyncHarness,
) -> None:
    first = make_operation(sync_harness.first_context, logical_clock=1)
    hidden = make_operation(sync_harness.second_context, logical_clock=1)
    second = make_operation(sync_harness.first_context, logical_clock=2)
    await sync_harness.service.push(sync_harness.first_context, [first])
    await sync_harness.service.push(sync_harness.second_context, [hidden])
    await sync_harness.service.push(sync_harness.first_context, [second])

    page = await sync_harness.service.pull(
        sync_harness.first_context,
        after=0,
        limit=50,
    )
    empty = await sync_harness.service.pull(
        sync_harness.first_context,
        after=page.next_cursor,
        limit=50,
    )

    assert [item.operation_id for item in page.operations] == [
        first.operation_id,
        second.operation_id,
    ]
    assert [item.server_sequence for item in page.operations] == sorted(
        item.server_sequence for item in page.operations
    )
    assert page.next_cursor == page.operations[-1].server_sequence
    assert empty.operations == []
    assert empty.next_cursor == page.next_cursor


@pytest.mark.anyio
async def test_pull_caps_a_service_page_at_200(sync_harness: SyncHarness) -> None:
    operations = [
        make_operation(sync_harness.first_context, logical_clock=index)
        for index in range(205)
    ]
    await sync_harness.service.push(sync_harness.first_context, operations)

    page = await sync_harness.service.pull(
        sync_harness.first_context,
        after=0,
        limit=500,
    )

    assert len(page.operations) == 200


@pytest.fixture
async def sync_api(
    sync_harness: SyncHarness,
) -> AsyncIterator[tuple[AsyncClient, str]]:
    auth_service = AuthService(
        sync_harness.session_factory,
        AuthSettings(
            bootstrap_token="test-bootstrap-token-at-least-32-bytes",
            token_signing_key=TOKEN_SIGNING_KEY,
            access_token_ttl=timedelta(minutes=15),
        ),
    )
    application = FastAPI()
    application.state.auth_service = auth_service
    application.state.sync_service = sync_harness.service
    application.include_router(sync_router)
    token = auth_service.access_tokens.issue(
        sync_harness.first_context.account_id,
        sync_harness.first_context.device_id,
    )
    transport = ASGITransport(app=application)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        yield client, token


@pytest.mark.anyio
async def test_sync_routes_require_bearer_and_exact_device_header(
    sync_api: tuple[AsyncClient, str],
    sync_harness: SyncHarness,
) -> None:
    client, token = sync_api
    operation = make_operation(sync_harness.first_context)
    payload = {
        "operations": [operation.model_dump(mode="json", by_alias=True)],
    }

    missing_bearer = await client.post(
        "/v1/sync/push",
        headers={"X-Device-Id": str(sync_harness.first_context.device_id)},
        json=payload,
    )
    missing_device = await client.post(
        "/v1/sync/push",
        headers={"Authorization": f"Bearer {token}"},
        json=payload,
    )
    mismatched_device = await client.post(
        "/v1/sync/push",
        headers={
            "Authorization": f"Bearer {token}",
            "X-Device-Id": str(sync_harness.second_context.device_id),
        },
        json=payload,
    )

    assert missing_bearer.status_code == 401
    assert missing_device.status_code == 422
    assert mismatched_device.status_code == 403
    assert mismatched_device.json() == {
        "detail": "Device identity is not authorized.",
    }
    assert await sync_harness.count(sync_harness.first_context.account_id) == 0


@pytest.mark.anyio
async def test_sync_api_returns_only_opaque_account_scoped_operations(
    sync_api: tuple[AsyncClient, str],
    sync_harness: SyncHarness,
) -> None:
    client, token = sync_api
    visible = make_operation(sync_harness.first_context)
    hidden = make_operation(
        sync_harness.second_context,
        operation_id=visible.operation_id,
        ciphertext=b"other-account-ciphertext",
    )
    await sync_harness.service.push(sync_harness.second_context, [hidden])
    headers = {
        "Authorization": f"Bearer {token}",
        "X-Device-Id": str(sync_harness.first_context.device_id),
    }

    pushed = await client.post(
        "/v1/sync/push",
        headers=headers,
        json={"operations": [visible.model_dump(mode="json", by_alias=True)]},
    )
    pulled = await client.get("/v1/sync/pull?after=0&limit=50", headers=headers)

    assert pushed.status_code == 200
    assert pushed.json() == {
        "accepted": [str(visible.operation_id)],
        "duplicates": [],
        "rejected": [],
    }
    assert pulled.status_code == 200
    body = pulled.json()
    assert [item["operationId"] for item in body["operations"]] == [
        str(visible.operation_id),
    ]
    assert body["operations"][0]["payloadNonce"]
    assert body["operations"][0]["payloadCiphertext"]
    serialized_keys = set().union(*(item.keys() for item in body["operations"]))
    assert serialized_keys.isdisjoint({"title", "notes", "prompt", "feedback"})
