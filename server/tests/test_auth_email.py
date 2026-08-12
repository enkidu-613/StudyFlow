from __future__ import annotations

from collections.abc import AsyncIterator
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import pytest
from fastapi import Depends, FastAPI
from httpx import ASGITransport, AsyncClient, Response
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from server.app.auth.routes import (
    get_auth_service,
    get_user_context,
    router as auth_router,
)
from server.app.auth.service import AuthService, AuthSettings
from server.app.db.context import UserContext
from server.app.db.models import Base, User, UserSession


TOKEN_SIGNING_KEY = "test-signing-key-at-least-32-bytes-long"
PASSWORD = "Correct-Horse-1"


@dataclass
class MutableClock:
    current: datetime

    def now(self) -> datetime:
        return self.current

    def advance(self, delta: timedelta) -> None:
        self.current += delta


class AuthClient:
    def __init__(
        self,
        client: AsyncClient,
        service: AuthService,
        clock: MutableClock,
        session_factory: async_sessionmaker[AsyncSession],
    ) -> None:
        self.client = client
        self.service = service
        self.clock = clock
        self.session_factory = session_factory
        self.email: str | None = None
        self.access_token: str | None = None
        self.refresh_token: str | None = None

    async def register(
        self,
        *,
        email: str = "user@example.com",
        password: str = PASSWORD,
    ) -> Response:
        response = await self.client.post(
            "/v1/auth/register",
            json={"email": email, "password": password},
        )
        if response.status_code == 201:
            self._remember(response)
        return response

    async def login(
        self,
        *,
        email: str = "user@example.com",
        password: str = PASSWORD,
    ) -> Response:
        response = await self.client.post(
            "/v1/auth/login",
            json={"email": email, "password": password},
        )
        if response.status_code == 200:
            self._remember(response)
        return response

    def _remember(self, response: Response) -> None:
        body = response.json()
        self.email = body["email"]
        self.access_token = body["access_token"]
        self.refresh_token = body["refresh_token"]

    @property
    def authorization_headers(self) -> dict[str, str]:
        assert self.access_token is not None
        return {"Authorization": f"Bearer {self.access_token}"}


@pytest.fixture
async def auth_client() -> AsyncIterator[AuthClient]:
    engine = create_async_engine(
        "sqlite+aiosqlite://",
        poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    clock = MutableClock(datetime(2026, 8, 12, 3, 0, tzinfo=UTC))
    settings = AuthSettings(
        token_signing_key=TOKEN_SIGNING_KEY,
        access_token_ttl=timedelta(minutes=15),
        refresh_token_ttl=timedelta(days=30),
    )
    service = AuthService(session_factory, settings, clock=clock.now)
    application = FastAPI()
    application.include_router(auth_router)

    @application.get("/test/user-context")
    async def user_context_endpoint(
        context: UserContext = Depends(get_user_context),
    ) -> dict[str, str]:
        return {"user_id": str(context.user_id), "email": context.email}

    application.dependency_overrides[get_auth_service] = lambda: service
    transport = ASGITransport(app=application)

    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        yield AuthClient(client, service, clock, session_factory)

    application.dependency_overrides.clear()
    await engine.dispose()


@pytest.mark.anyio
async def test_register_returns_201_without_password_hash(auth_client: AuthClient) -> None:
    response = await auth_client.register()

    assert response.status_code == 201
    body = response.json()
    assert body["email"] == "user@example.com"
    assert "password_hash" not in body
    assert body["access_token"]
    assert body["refresh_token"]


@pytest.mark.anyio
async def test_duplicate_email_returns_409(auth_client: AuthClient) -> None:
    first = await auth_client.register()
    second = await auth_client.register()

    assert first.status_code == 201
    assert second.status_code == 409


@pytest.mark.anyio
async def test_invalid_email_returns_422(auth_client: AuthClient) -> None:
    response = await auth_client.register(email="not-an-email")

    assert response.status_code == 422


@pytest.mark.anyio
async def test_short_password_returns_422(auth_client: AuthClient) -> None:
    response = await auth_client.register(password="short")

    assert response.status_code == 422


@pytest.mark.anyio
async def test_login_with_correct_credentials_returns_session(auth_client: AuthClient) -> None:
    await auth_client.register()

    response = await auth_client.login()

    assert response.status_code == 200
    body = response.json()
    assert body["email"] == "user@example.com"
    assert body["access_token"]


@pytest.mark.anyio
async def test_login_ignores_email_case(auth_client: AuthClient) -> None:
    await auth_client.register(email="user@example.com")

    response = await auth_client.login(email="USER@Example.com")

    assert response.status_code == 200


@pytest.mark.anyio
async def test_login_with_wrong_password_returns_401(auth_client: AuthClient) -> None:
    await auth_client.register()

    response = await auth_client.login(password="wrong-password-here")

    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid credentials."


@pytest.mark.anyio
async def test_login_with_unknown_email_returns_401(auth_client: AuthClient) -> None:
    response = await auth_client.login(email="nobody@example.com")

    assert response.status_code == 401


@pytest.mark.anyio
async def test_refresh_rotates_session(auth_client: AuthClient) -> None:
    created = await auth_client.register()
    old_refresh = created.json()["refresh_token"]

    response = await auth_client.client.post(
        "/v1/auth/refresh",
        json={"refresh_token": old_refresh},
    )

    assert response.status_code == 200
    new_refresh = response.json()["refresh_token"]
    assert new_refresh != old_refresh


@pytest.mark.anyio
async def test_reusing_old_refresh_token_returns_401(auth_client: AuthClient) -> None:
    created = await auth_client.register()
    old_refresh = created.json()["refresh_token"]

    await auth_client.client.post(
        "/v1/auth/refresh",
        json={"refresh_token": old_refresh},
    )
    second = await auth_client.client.post(
        "/v1/auth/refresh",
        json={"refresh_token": old_refresh},
    )

    assert second.status_code == 401


@pytest.mark.anyio
async def test_logout_revokes_refresh_token(auth_client: AuthClient) -> None:
    created = await auth_client.register()
    refresh_token = created.json()["refresh_token"]

    logout = await auth_client.client.post(
        "/v1/auth/logout",
        json={"refresh_token": refresh_token},
    )
    refresh_after_logout = await auth_client.client.post(
        "/v1/auth/refresh",
        json={"refresh_token": refresh_token},
    )

    assert logout.status_code == 204
    assert refresh_after_logout.status_code == 401


@pytest.mark.anyio
async def test_session_endpoint_returns_user_identity(auth_client: AuthClient) -> None:
    await auth_client.register()

    response = await auth_client.client.get(
        "/v1/auth/session",
        headers=auth_client.authorization_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["email"] == "user@example.com"
    assert body["user_id"]


@pytest.mark.anyio
async def test_password_is_stored_as_argon2id_hash(auth_client: AuthClient) -> None:
    await auth_client.register()

    async with auth_client.session_factory() as session:
        user = (await session.execute(select(User))).scalar_one()

    assert user.password_hash.startswith("$argon2id$")


@pytest.mark.anyio
async def test_refresh_sessions_are_revoked_on_reuse(
    auth_client: AuthClient,
) -> None:
    created = await auth_client.register()
    refresh_token = created.json()["refresh_token"]
    await auth_client.client.post("/v1/auth/refresh", json={"refresh_token": refresh_token})

    async with auth_client.session_factory() as session:
        sessions = (await session.execute(select(UserSession))).scalars().all()

    assert len(sessions) == 2
    revoked = [row for row in sessions if row.revoked_at is not None]
    assert len(revoked) == 1
