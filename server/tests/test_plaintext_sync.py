from __future__ import annotations

from collections.abc import AsyncIterator
from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest
from fastapi import Depends, FastAPI
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from server.app.auth.routes import get_auth_service, router as auth_router
from server.app.auth.service import AuthService, AuthSettings
from server.app.db.context import UserContext
from server.app.db.models import Base, User, UserSyncOperation
from server.app.sync.repository import SyncOperationRepository
from server.app.sync.routes import get_sync_service, router as sync_router
from server.app.sync.service import SyncService


TOKEN_SIGNING_KEY = "test-signing-key-at-least-32-bytes-long"
PASSWORD = "Correct-Horse-1"


@dataclass
class MutableClock:
    current: datetime

    def now(self) -> datetime:
        return self.current


class SyncHarness:
    def __init__(
        self,
        client: AsyncClient,
        service: AuthService,
        session_factory: async_sessionmaker[AsyncSession],
    ) -> None:
        self.client = client
        self.service = service
        self.session_factory = session_factory
        self.first_access_token: str | None = None
        self.second_access_token: str | None = None

    async def register(self, email: str) -> None:
        response = await self.client.post(
            "/v1/auth/register",
            json={"email": email, "password": PASSWORD},
        )
        assert response.status_code == 201

    async def login(self, email: str) -> str:
        response = await self.client.post(
            "/v1/auth/login",
            json={"email": email, "password": PASSWORD},
        )
        assert response.status_code == 200
        return response.json()["access_token"]

    async def push(
        self,
        token: str,
        operation: dict[str, object],
    ) -> tuple[int, dict[str, object]]:
        response = await self.client.post(
            "/v1/sync/push",
            headers={"Authorization": f"Bearer {token}"},
            json={"operations": [operation]},
        )
        return response.status_code, response.json()

    async def pull(
        self,
        token: str,
        after: int = 0,
    ) -> tuple[int, dict[str, object]]:
        response = await self.client.get(
            "/v1/sync/pull",
            headers={"Authorization": f"Bearer {token}"},
            params={"after": after},
        )
        return response.status_code, response.json()


def make_operation(
    *,
    operation_id: UUID | None = None,
    record_id: UUID | None = None,
    payload: dict[str, object] | None = None,
    entity_type: str = "task",
    is_tombstone: bool = False,
) -> dict[str, object]:
    return {
        "operationId": str(operation_id or uuid4()),
        "recordId": str(record_id or uuid4()),
        "logicalClock": 0,
        "entityType": entity_type,
        "payload": payload if payload is not None else {"title": "Read chapter 1"},
        "isTombstone": is_tombstone,
        "schemaVersion": 1,
    }


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
    clock = MutableClock(datetime(2026, 8, 12, 3, 0, tzinfo=UTC))
    settings = AuthSettings(token_signing_key=TOKEN_SIGNING_KEY)
    auth_service = AuthService(session_factory, settings, clock=clock.now)
    sync_service = SyncService(SyncOperationRepository(session_factory))
    application = FastAPI()
    application.include_router(auth_router)
    application.include_router(sync_router)
    application.dependency_overrides[get_auth_service] = lambda: auth_service
    application.dependency_overrides[get_sync_service] = lambda: sync_service

    transport = ASGITransport(app=application)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        harness = SyncHarness(client, auth_service, session_factory)
        await harness.register("first@example.com")
        await harness.register("second@example.com")
        harness.first_access_token = await harness.login("first@example.com")
        harness.second_access_token = await harness.login("second@example.com")
        yield harness

    application.dependency_overrides.clear()
    await engine.dispose()


@pytest.mark.anyio
async def test_push_accepts_json_payload_and_returns_accepted(
    sync_harness: SyncHarness,
) -> None:
    operation = make_operation()
    status_code, body = await sync_harness.push(
        sync_harness.first_access_token or "",
        operation,
    )

    assert status_code == 200
    assert body["accepted"] == [operation["operationId"]]


@pytest.mark.anyio
async def test_push_rejects_missing_operation_id(sync_harness: SyncHarness) -> None:
    operation = make_operation()
    operation.pop("operationId")

    response = await sync_harness.client.post(
        "/v1/sync/push",
        headers={
            "Authorization": f"Bearer {sync_harness.first_access_token or ''}",
        },
        json={"operations": [operation]},
    )

    assert response.status_code == 422


@pytest.mark.anyio
async def test_push_rejects_unknown_entity_type(sync_harness: SyncHarness) -> None:
    operation = make_operation(entity_type="unknown")

    response = await sync_harness.client.post(
        "/v1/sync/push",
        headers={
            "Authorization": f"Bearer {sync_harness.first_access_token or ''}",
        },
        json={"operations": [operation]},
    )

    assert response.status_code == 422


@pytest.mark.anyio
async def test_push_rejects_invalid_schema_version(sync_harness: SyncHarness) -> None:
    operation = make_operation()
    operation["schemaVersion"] = 99

    response = await sync_harness.client.post(
        "/v1/sync/push",
        headers={
            "Authorization": f"Bearer {sync_harness.first_access_token or ''}",
        },
        json={"operations": [operation]},
    )

    assert response.status_code == 422


@pytest.mark.anyio
async def test_push_ignores_extra_user_id_field(sync_harness: SyncHarness) -> None:
    operation = make_operation()
    operation["userId"] = "some-other-user"

    response = await sync_harness.client.post(
        "/v1/sync/push",
        headers={
            "Authorization": f"Bearer {sync_harness.first_access_token or ''}",
        },
        json={"operations": [operation]},
    )

    assert response.status_code == 422  # extra field forbidden


@pytest.mark.anyio
async def test_push_is_idempotent_per_user_and_operation(
    sync_harness: SyncHarness,
) -> None:
    operation = make_operation()
    first = await sync_harness.push(sync_harness.first_access_token or "", operation)
    second = await sync_harness.push(sync_harness.first_access_token or "", operation)

    assert first[1]["accepted"] == [operation["operationId"]]
    assert second[1]["duplicates"] == [operation["operationId"]]


@pytest.mark.anyio
async def test_same_operation_id_with_different_payload_returns_409(
    sync_harness: SyncHarness,
) -> None:
    operation = make_operation()
    await sync_harness.push(sync_harness.first_access_token or "", operation)

    changed = dict(operation)
    changed["payload"] = {"title": "Changed content"}
    status_code, _ = await sync_harness.push(sync_harness.first_access_token or "", changed)

    assert status_code == 409


@pytest.mark.anyio
async def test_pull_returns_only_authenticated_users_operations(
    sync_harness: SyncHarness,
) -> None:
    first_operation = make_operation()
    second_operation = make_operation()
    await sync_harness.push(sync_harness.first_access_token or "", first_operation)
    await sync_harness.push(sync_harness.second_access_token or "", second_operation)

    first_status, first_body = await sync_harness.pull(
        sync_harness.first_access_token or "",
    )
    second_status, second_body = await sync_harness.pull(
        sync_harness.second_access_token or "",
    )

    assert first_status == 200
    assert second_status == 200
    first_ids = {op["operationId"] for op in first_body["operations"]}
    second_ids = {op["operationId"] for op in second_body["operations"]}
    assert str(first_operation["operationId"]) in first_ids
    assert str(first_operation["operationId"]) not in second_ids
    assert str(second_operation["operationId"]) in second_ids
    assert str(second_operation["operationId"]) not in first_ids


@pytest.mark.anyio
async def test_pull_advances_cursor(sync_harness: SyncHarness) -> None:
    first = make_operation()
    second = make_operation()
    await sync_harness.push(sync_harness.first_access_token or "", first)
    await sync_harness.push(sync_harness.first_access_token or "", second)

    page_one_status, page_one = await sync_harness.pull(
        sync_harness.first_access_token or "",
        after=0,
    )
    assert page_one_status == 200
    next_cursor = page_one["next_cursor"]

    page_two_status, page_two = await sync_harness.pull(
        sync_harness.first_access_token or "",
        after=next_cursor,
    )
    assert page_two_status == 200
    assert page_two["operations"] == []
    assert page_two["next_cursor"] == next_cursor


@pytest.mark.anyio
async def test_tombstone_operation_allows_empty_payload(
    sync_harness: SyncHarness,
) -> None:
    operation = make_operation(payload={}, is_tombstone=True)

    status_code, body = await sync_harness.push(
        sync_harness.first_access_token or "",
        operation,
    )

    assert status_code == 200
    assert body["accepted"] == [operation["operationId"]]


@pytest.mark.anyio
async def test_stored_payload_uses_json_column(sync_harness: SyncHarness) -> None:
    operation = make_operation(payload={"title": "Persisted task", "tags": ["a"]})
    await sync_harness.push(sync_harness.first_access_token or "", operation)

    async with sync_harness.session_factory() as session:
        stored = (
            await session.execute(select(UserSyncOperation))
        ).scalar_one()

    assert stored.payload == {"title": "Persisted task", "tags": ["a"]}
