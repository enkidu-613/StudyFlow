from __future__ import annotations

from collections.abc import AsyncIterator
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from fastapi import Depends, FastAPI
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from server.app.auth.password_blacklist import NoopBreachedPasswordChecker
from server.app.auth.routes import get_auth_service, router as auth_router
from server.app.auth.service import AuthService, AuthSettings
from server.app.backups.repository import BackupRepository
from server.app.backups.routes import get_backup_service, router as backup_router
from server.app.backups.service import BackupService, BackupSettings
from server.app.db.models import Base
from server.app.sync.repository import SyncOperationRepository
from server.app.sync.routes import get_sync_service, router as sync_router
from server.app.sync.service import SyncService


PASSWORD = "Correct-Horse-1"
TOKEN_SIGNING_KEY = "test-signing-key-at-least-32-bytes-long"


@dataclass
class MutableClock:
    current: datetime

    def now(self) -> datetime:
        return self.current


@dataclass(frozen=True, slots=True)
class BackupRouteHarness:
    client: AsyncClient
    service: AuthService
    session_factory: async_sessionmaker[AsyncSession]
    clock: MutableClock


@pytest.fixture
async def harness() -> AsyncIterator[BackupRouteHarness]:
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
    backup_service = BackupService(
        BackupRepository(session_factory),
        BackupSettings(max_backups_per_user=5),
    )
    sync_service = SyncService(SyncOperationRepository(session_factory))

    application = FastAPI()
    application.include_router(auth_router)
    application.include_router(sync_router)
    application.include_router(backup_router)
    application.dependency_overrides[get_auth_service] = lambda: auth_service
    application.dependency_overrides[get_backup_service] = lambda: backup_service
    application.dependency_overrides[get_sync_service] = lambda: sync_service

    transport = ASGITransport(app=application)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        yield BackupRouteHarness(
            client=client,
            service=auth_service,
            session_factory=session_factory,
            clock=clock,
        )

    application.dependency_overrides.clear()
    await engine.dispose()


async def _register(client: AsyncClient, email: str) -> str:
    response = await client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD},
    )
    assert response.status_code == 201
    return response.json()["access_token"]


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.mark.anyio
async def test_create_backup_route_returns_201(harness: BackupRouteHarness) -> None:
    token = await _register(harness.client, "route-a@example.com")

    response = await harness.client.post(
        "/v1/backups",
        headers=_auth(token),
        json={"name": "路由备份"},
    )

    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "路由备份"
    assert body["operation_count"] == 0
    assert "payload" not in body


@pytest.mark.anyio
async def test_create_backup_with_blank_name_returns_422(
    harness: BackupRouteHarness,
) -> None:
    token = await _register(harness.client, "route-b@example.com")

    response = await harness.client.post(
        "/v1/backups",
        headers=_auth(token),
        json={"name": "   "},
    )

    assert response.status_code == 422


@pytest.mark.anyio
async def test_create_backup_reaches_limit_returns_409(
    harness: BackupRouteHarness,
) -> None:
    token = await _register(harness.client, "route-c@example.com")
    for i in range(5):
        response = await harness.client.post(
            "/v1/backups",
            headers=_auth(token),
            json={"name": f"备份 {i}"},
        )
        assert response.status_code == 201

    sixth = await harness.client.post(
        "/v1/backups",
        headers=_auth(token),
        json={"name": "第六个"},
    )

    assert sixth.status_code == 409
    assert "5" in sixth.json()["detail"]


@pytest.mark.anyio
async def test_rename_foreign_backup_returns_404(harness: BackupRouteHarness) -> None:
    token_a = await _register(harness.client, "route-d@example.com")
    token_b = await _register(harness.client, "route-e@example.com")
    created = await harness.client.post(
        "/v1/backups",
        headers=_auth(token_a),
        json={"name": "A 的备份"},
    )
    backup_id = created.json()["backup_id"]

    renamed = await harness.client.patch(
        f"/v1/backups/{backup_id}",
        headers=_auth(token_b),
        json={"name": "偷改"},
    )

    assert renamed.status_code == 404


@pytest.mark.anyio
async def test_list_backups_requires_auth(harness: BackupRouteHarness) -> None:
    response = await harness.client.get("/v1/backups")

    assert response.status_code == 401


@pytest.mark.anyio
async def test_rename_blank_name_returns_422(harness: BackupRouteHarness) -> None:
    token = await _register(harness.client, "route-f@example.com")
    created = await harness.client.post(
        "/v1/backups",
        headers=_auth(token),
        json={},
    )
    backup_id = created.json()["backup_id"]

    renamed = await harness.client.patch(
        f"/v1/backups/{backup_id}",
        headers=_auth(token),
        json={"name": ""},
    )

    assert renamed.status_code == 422


async def _create_backups(client: AsyncClient, token: str, count: int) -> list[str]:
    ids: list[str] = []
    for i in range(count):
        response = await client.post(
            "/v1/backups",
            headers=_auth(token),
            json={"name": f"备份 {i}"},
        )
        assert response.status_code == 201
        ids.append(response.json()["backup_id"])
    return ids


@pytest.mark.anyio
async def test_batch_delete_removes_selected_backups(
    harness: BackupRouteHarness,
) -> None:
    token = await _register(harness.client, "route-g@example.com")
    ids = await _create_backups(harness.client, token, 3)

    response = await harness.client.post(
        "/v1/backups/batch-delete",
        headers=_auth(token),
        json={"backup_ids": ids[:2]},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["deleted"] == 2
    assert body["not_found"] == []

    remaining = await harness.client.get(
        "/v1/backups",
        headers=_auth(token),
    )
    assert len(remaining.json()["backups"]) == 1


@pytest.mark.anyio
async def test_batch_delete_reports_not_found_for_foreign_or_missing(
    harness: BackupRouteHarness,
) -> None:
    token_a = await _register(harness.client, "route-h@example.com")
    token_b = await _register(harness.client, "route-i@example.com")
    a_ids = await _create_backups(harness.client, token_a, 1)
    foreign_id = a_ids[0]
    missing_id = str(uuid4())

    response = await harness.client.post(
        "/v1/backups/batch-delete",
        headers=_auth(token_b),
        json={"backup_ids": [foreign_id, missing_id]},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["deleted"] == 0
    assert set(body["not_found"]) == {foreign_id, missing_id}

    # User A's backup must still exist (not deleted by user B).
    remaining = await harness.client.get(
        "/v1/backups",
        headers=_auth(token_a),
    )
    assert len(remaining.json()["backups"]) == 1


@pytest.mark.anyio
async def test_batch_delete_empty_ids_returns_422(
    harness: BackupRouteHarness,
) -> None:
    token = await _register(harness.client, "route-j@example.com")

    response = await harness.client.post(
        "/v1/backups/batch-delete",
        headers=_auth(token),
        json={"backup_ids": []},
    )

    assert response.status_code == 422


@pytest.mark.anyio
async def test_batch_delete_duplicate_ids_returns_422(
    harness: BackupRouteHarness,
) -> None:
    token = await _register(harness.client, "route-k@example.com")
    ids = await _create_backups(harness.client, token, 1)

    response = await harness.client.post(
        "/v1/backups/batch-delete",
        headers=_auth(token),
        json={"backup_ids": [ids[0], ids[0]]},
    )

    assert response.status_code == 422


@pytest.mark.anyio
async def test_batch_delete_requires_auth(harness: BackupRouteHarness) -> None:
    response = await harness.client.post(
        "/v1/backups/batch-delete",
        json={"backup_ids": [str(uuid4())]},
    )

    assert response.status_code == 401


@pytest.mark.anyio
async def test_batch_delete_is_idempotent(harness: BackupRouteHarness) -> None:
    token = await _register(harness.client, "route-l@example.com")
    ids = await _create_backups(harness.client, token, 2)

    first = await harness.client.post(
        "/v1/backups/batch-delete",
        headers=_auth(token),
        json={"backup_ids": ids},
    )
    second = await harness.client.post(
        "/v1/backups/batch-delete",
        headers=_auth(token),
        json={"backup_ids": ids},
    )

    assert first.json()["deleted"] == 2
    assert second.json()["deleted"] == 0
    assert set(second.json()["not_found"]) == set(ids)
