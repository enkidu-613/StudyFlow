from __future__ import annotations

from collections.abc import AsyncIterator
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient, Response
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from server.app.auth.models import PairingCode, RefreshSession
from server.app.auth.routes import get_auth_service, router as auth_router
from server.app.auth.service import AccessTokenCodec, AuthService, AuthSettings
from server.app.db.models import Account, Base, Device, SyncOperation


BOOTSTRAP_TOKEN = "test-bootstrap-token-not-a-production-secret"
TOKEN_SIGNING_KEY = "test-signing-key-at-least-32-bytes-long"
PASSWORD = "correct horse battery staple"
ACCOUNT_ENVELOPE = "ZW5jcnlwdGVkLWFjY291bnQtZGF0YS1rZXk="
FIRST_DEVICE_PUBLIC_KEY = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE="
SECOND_DEVICE_PUBLIC_KEY = "AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI="


@dataclass
class MutableClock:
    current: datetime

    def now(self) -> datetime:
        return self.current

    def advance(self, delta: timedelta) -> None:
        self.current += delta


class PairingCodeSequence:
    def __init__(self) -> None:
        self._next = 123456

    def __call__(self) -> str:
        code = f"{self._next:06d}"
        self._next += 1
        return code


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
        self.account_id: str | None = None
        self.device_id: str | None = None
        self.access_token: str | None = None
        self.refresh_token: str | None = None

    async def bootstrap(
        self,
        *,
        bootstrap_token: str = BOOTSTRAP_TOKEN,
        device_id: str | None = None,
        password: str = PASSWORD,
    ) -> Response:
        selected_device_id = device_id or str(uuid4())
        response = await self.client.post(
            "/v1/auth/bootstrap",
            headers={"X-StudyFlow-Bootstrap-Token": bootstrap_token},
            json={
                "password": password,
                "device_id": selected_device_id,
                "device_public_key": FIRST_DEVICE_PUBLIC_KEY,
                "encrypted_account_data_key_envelope": ACCOUNT_ENVELOPE,
            },
        )
        if response.is_success:
            self._remember(response)
        return response

    async def login(
        self,
        *,
        password: str = PASSWORD,
        device_id: str | None = None,
    ) -> Response:
        response = await self.client.post(
            "/v1/auth/login",
            json={
                "password": password,
                "device_id": device_id or self.device_id,
            },
        )
        if response.is_success:
            self._remember(response)
        return response

    async def create_pairing_code(
        self,
        *,
        target_device_id: str | None = None,
        target_device_public_key: str = SECOND_DEVICE_PUBLIC_KEY,
        envelope: str = ACCOUNT_ENVELOPE,
    ) -> tuple[Response, str]:
        selected_target_id = target_device_id or str(uuid4())
        response = await self.client.post(
            "/v1/devices/pairing-codes",
            headers=self.authorization_headers,
            json={
                "target_device_id": selected_target_id,
                "target_device_public_key": target_device_public_key,
                "encrypted_account_data_key_envelope": envelope,
            },
        )
        return response, selected_target_id

    async def pair(
        self,
        code: str,
        target_device_id: str,
        *,
        target_device_public_key: str = SECOND_DEVICE_PUBLIC_KEY,
    ) -> Response:
        return await self.client.post(
            "/v1/devices/pair",
            json={
                "code": code,
                "device_id": target_device_id,
                "device_public_key": target_device_public_key,
            },
        )

    @property
    def authorization_headers(self) -> dict[str, str]:
        assert self.access_token is not None
        return {"Authorization": f"Bearer {self.access_token}"}

    def _remember(self, response: Response) -> None:
        body = response.json()
        self.account_id = body["account_id"]
        self.device_id = body["device_id"]
        self.access_token = body["access_token"]
        self.refresh_token = body["refresh_token"]


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
    clock = MutableClock(datetime(2026, 8, 11, 3, 0, tzinfo=UTC))
    settings = AuthSettings(
        bootstrap_token=BOOTSTRAP_TOKEN,
        token_signing_key=TOKEN_SIGNING_KEY,
        access_token_ttl=timedelta(minutes=15),
        refresh_token_ttl=timedelta(days=30),
        pairing_code_ttl=timedelta(minutes=10),
    )
    service = AuthService(
        session_factory,
        settings,
        clock=clock.now,
        pairing_code_generator=PairingCodeSequence(),
    )
    application = FastAPI()
    application.include_router(auth_router)
    application.dependency_overrides[get_auth_service] = lambda: service
    transport = ASGITransport(app=application)

    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        yield AuthClient(client, service, clock, session_factory)

    application.dependency_overrides.clear()
    await engine.dispose()


@pytest.mark.anyio
async def test_bootstrap_requires_server_token_and_can_run_only_once(auth_client: AuthClient) -> None:
    rejected = await auth_client.bootstrap(bootstrap_token="wrong-token")
    created = await auth_client.bootstrap()
    repeated = await auth_client.bootstrap()

    assert rejected.status_code == 403
    assert created.status_code == 201
    assert repeated.status_code == 409
    assert created.json()["account_id"]
    assert created.json()["device_id"] == auth_client.device_id

    async with auth_client.session_factory() as session:
        account = (await session.execute(select(Account))).scalar_one()
        device = (await session.execute(select(Device))).scalar_one()

    assert account.password_hash != PASSWORD
    assert account.password_hash.startswith("$argon2id$")
    assert device.account_id == account.account_id
    assert device.encrypted_account_data_key_envelope == ACCOUNT_ENVELOPE


@pytest.mark.anyio
async def test_login_returns_device_bound_tokens_and_rejects_wrong_password(
    auth_client: AuthClient,
) -> None:
    await auth_client.bootstrap()

    rejected = await auth_client.login(password="not the password")
    accepted = await auth_client.login()

    assert rejected.status_code == 401
    assert accepted.status_code == 200
    body = accepted.json()
    identity = auth_client.service.access_tokens.decode(body["access_token"])
    assert str(identity.account_id) == body["account_id"]
    assert str(identity.device_id) == body["device_id"]
    assert body["encrypted_account_data_key_envelope"] == ACCOUNT_ENVELOPE
    assert body["token_type"] == "bearer"
    assert body["expires_in"] == 900


@pytest.mark.anyio
async def test_refresh_token_rotates_and_the_previous_token_cannot_be_reused(
    auth_client: AuthClient,
) -> None:
    await auth_client.bootstrap()
    previous_refresh_token = auth_client.refresh_token
    assert previous_refresh_token is not None

    rotated = await auth_client.client.post(
        "/v1/auth/refresh",
        json={"refresh_token": previous_refresh_token},
    )
    replayed = await auth_client.client.post(
        "/v1/auth/refresh",
        json={"refresh_token": previous_refresh_token},
    )

    assert rotated.status_code == 200
    assert rotated.json()["refresh_token"] != previous_refresh_token
    assert replayed.status_code == 401

    async with auth_client.session_factory() as session:
        sessions = list((await session.execute(select(RefreshSession))).scalars())
    assert len(sessions) == 2
    assert sum(session.revoked_at is not None for session in sessions) == 1


@pytest.mark.anyio
async def test_pairing_code_is_six_digits_hashed_at_rest_and_cannot_be_reused(
    auth_client: AuthClient,
) -> None:
    await auth_client.bootstrap()
    created, target_device_id = await auth_client.create_pairing_code()
    code = created.json()["code"]

    first = await auth_client.pair(code, target_device_id)
    second = await auth_client.pair(code, target_device_id)

    assert created.status_code == 201
    assert len(code) == 6 and code.isdigit()
    assert first.status_code == 200
    assert first.json()["account_id"] == auth_client.account_id
    assert first.json()["device_id"] == target_device_id
    assert first.json()["encrypted_account_data_key_envelope"] == ACCOUNT_ENVELOPE
    assert second.status_code == 410

    async with auth_client.session_factory() as session:
        pairing = (await session.execute(select(PairingCode))).scalar_one()
    assert pairing.code_digest != code.encode()
    assert len(pairing.code_digest) == 32
    assert pairing.consumed_at is not None


@pytest.mark.anyio
async def test_pairing_code_expires_after_ten_minutes(auth_client: AuthClient) -> None:
    await auth_client.bootstrap()
    created, target_device_id = await auth_client.create_pairing_code()
    auth_client.clock.advance(timedelta(minutes=10))

    response = await auth_client.pair(created.json()["code"], target_device_id)

    assert response.status_code == 410


@pytest.mark.anyio
async def test_pairing_code_is_bound_to_target_device_and_public_key(
    auth_client: AuthClient,
) -> None:
    await auth_client.bootstrap()
    created, target_device_id = await auth_client.create_pairing_code()
    code = created.json()["code"]

    wrong_device = await auth_client.pair(code, str(uuid4()))
    wrong_key = await auth_client.pair(
        code,
        target_device_id,
        target_device_public_key=FIRST_DEVICE_PUBLIC_KEY,
    )
    accepted = await auth_client.pair(code, target_device_id)

    assert wrong_device.status_code == 403
    assert wrong_key.status_code == 403
    assert accepted.status_code == 200


@pytest.mark.anyio
async def test_pairing_rejects_a_non_x25519_public_key(auth_client: AuthClient) -> None:
    await auth_client.bootstrap()

    response, _ = await auth_client.create_pairing_code(
        target_device_public_key="dG9vLXNob3J0",
    )

    assert response.status_code == 422


@pytest.mark.anyio
async def test_account_cannot_pair_revoke_or_authenticate_as_another_accounts_device(
    auth_client: AuthClient,
) -> None:
    await auth_client.bootstrap()
    account_a_id = UUID(auth_client.account_id or "")
    account_a_device_id = UUID(auth_client.device_id or "")
    account_b_id = uuid4()
    account_b_device_id = uuid4()

    async with auth_client.session_factory() as session:
        async with session.begin():
            session.add(
                Account(
                    account_id=account_b_id,
                    password_hash=auth_client.service.hash_password(PASSWORD),
                ),
            )
            session.add(
                Device(
                    account_id=account_b_id,
                    device_id=account_b_device_id,
                    public_key=SECOND_DEVICE_PUBLIC_KEY,
                    encrypted_account_data_key_envelope=ACCOUNT_ENVELOPE,
                ),
            )

    pairing, _ = await auth_client.create_pairing_code(
        target_device_id=str(account_b_device_id),
    )
    revoke = await auth_client.client.post(
        "/v1/devices/revoke",
        headers=auth_client.authorization_headers,
        json={"device_id": str(account_b_device_id)},
    )
    cross_owned_token = AccessTokenCodec(
        TOKEN_SIGNING_KEY,
        clock=auth_client.clock.now,
        ttl=timedelta(minutes=15),
    ).issue(account_a_id, account_b_device_id)
    session_response = await auth_client.client.get(
        "/v1/auth/session",
        headers={"Authorization": f"Bearer {cross_owned_token}"},
    )

    assert pairing.status_code == 409
    assert revoke.status_code == 404
    assert session_response.status_code == 401

    async with auth_client.session_factory() as session:
        account_b_device = await session.get(
            Device,
            {"account_id": account_b_id, "device_id": account_b_device_id},
        )
        account_a_device = await session.get(
            Device,
            {"account_id": account_a_id, "device_id": account_a_device_id},
        )
    assert account_b_device is not None and account_b_device.revoked_at is None
    assert account_a_device is not None and account_a_device.revoked_at is None


@pytest.mark.anyio
async def test_revocation_invalidates_access_and_refresh_without_deleting_encrypted_records(
    auth_client: AuthClient,
) -> None:
    await auth_client.bootstrap()
    account_id = UUID(auth_client.account_id or "")
    device_id = UUID(auth_client.device_id or "")
    access_token = auth_client.access_token
    refresh_token = auth_client.refresh_token

    async with auth_client.session_factory() as session:
        async with session.begin():
            session.add(
                SyncOperation(
                    server_sequence=1,
                    account_id=account_id,
                    device_id=device_id,
                    operation_id=uuid4(),
                    record_id=uuid4(),
                    payload_nonce=b"opaque-nonce",
                    payload_ciphertext=b"opaque-ciphertext",
                ),
            )

    revoked = await auth_client.client.post(
        "/v1/devices/revoke",
        headers=auth_client.authorization_headers,
        json={"device_id": str(device_id)},
    )
    protected = await auth_client.client.get(
        "/v1/auth/session",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    refreshed = await auth_client.client.post(
        "/v1/auth/refresh",
        json={"refresh_token": refresh_token},
    )

    assert revoked.status_code == 204
    assert protected.status_code == 401
    assert refreshed.status_code == 401

    async with auth_client.session_factory() as session:
        account_count = await session.scalar(select(func.count()).select_from(Account))
        operation_count = await session.scalar(
            select(func.count()).select_from(SyncOperation),
        )
    assert account_count == 1
    assert operation_count == 1
