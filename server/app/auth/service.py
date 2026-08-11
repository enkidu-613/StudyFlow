from __future__ import annotations

import asyncio
import hmac
import os
import secrets
from collections import OrderedDict
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from hashlib import sha256
from uuid import UUID, uuid4

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError
from argon2.low_level import Type
from sqlalchemy import and_, case, or_, select, text, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from server.app.auth.models import BootstrapState, PairingCode, RefreshSession
from server.app.db.models import Account, Device


@dataclass(frozen=True, slots=True)
class AuthSettings:
    bootstrap_token: str
    token_signing_key: str
    access_token_ttl: timedelta = timedelta(minutes=15)
    refresh_token_ttl: timedelta = timedelta(days=30)
    pairing_code_ttl: timedelta = timedelta(minutes=10)
    pairing_code_attempt_limit: int = 5
    pairing_source_attempt_limit: int = 20
    pairing_source_window: timedelta = timedelta(minutes=10)
    pairing_source_cache_size: int = 4096

    @classmethod
    def from_env(cls) -> AuthSettings:
        bootstrap_token = os.getenv("STUDYFLOW_BOOTSTRAP_TOKEN")
        token_signing_key = os.getenv("STUDYFLOW_TOKEN_SIGNING_KEY")
        if not bootstrap_token or not token_signing_key:
            raise ValueError(
                "STUDYFLOW_BOOTSTRAP_TOKEN and STUDYFLOW_TOKEN_SIGNING_KEY must be set",
            )
        if len(bootstrap_token.encode("utf-8")) < 32:
            raise ValueError("STUDYFLOW_BOOTSTRAP_TOKEN must contain at least 32 bytes")
        if len(token_signing_key.encode("utf-8")) < 32:
            raise ValueError("STUDYFLOW_TOKEN_SIGNING_KEY must contain at least 32 bytes")
        return cls(
            bootstrap_token=bootstrap_token,
            token_signing_key=token_signing_key,
        )


@dataclass(frozen=True, slots=True)
class AuthIdentity:
    account_id: UUID
    device_id: UUID


@dataclass(frozen=True, slots=True)
class AuthSession:
    account_id: UUID
    device_id: UUID
    access_token: str
    refresh_token: str
    expires_in: int
    encrypted_account_data_key_envelope: str


@dataclass(frozen=True, slots=True)
class CreatedPairingCode:
    code: str
    expires_at: datetime


class AuthServiceError(RuntimeError):
    def __init__(self, status_code: int, detail: str) -> None:
        self.status_code = status_code
        self.detail = detail
        super().__init__(detail)


@dataclass(slots=True)
class _PairingSourceWindow:
    started_at: datetime
    attempts: int


class PairingSourceLimiter:
    def __init__(
        self,
        signing_key: str,
        *,
        attempt_limit: int,
        window: timedelta,
        max_sources: int,
    ) -> None:
        if attempt_limit < 1 or window <= timedelta(0) or max_sources < 1:
            raise ValueError("Pairing source limiter settings must be positive.")
        self._signing_key = signing_key.encode("utf-8")
        self._attempt_limit = attempt_limit
        self._window = window
        self._max_sources = max_sources
        self._windows: OrderedDict[bytes, _PairingSourceWindow] = OrderedDict()
        self._lock = asyncio.Lock()

    async def consume(self, source: str, now: datetime) -> bool:
        source_digest = hmac.new(
            self._signing_key,
            f"pairing-source\x00{source}".encode("utf-8"),
            sha256,
        ).digest()
        async with self._lock:
            current = self._windows.get(source_digest)
            if current is None or now - current.started_at >= self._window:
                self._windows[source_digest] = _PairingSourceWindow(
                    started_at=now,
                    attempts=1,
                )
                self._windows.move_to_end(source_digest)
                while len(self._windows) > self._max_sources:
                    self._windows.popitem(last=False)
                return True
            self._windows.move_to_end(source_digest)
            if current.attempts >= self._attempt_limit:
                return False
            current.attempts += 1
            return True


class AccessTokenCodec:
    def __init__(
        self,
        signing_key: str,
        *,
        clock: Callable[[], datetime],
        ttl: timedelta,
    ) -> None:
        self._signing_key = signing_key
        self._clock = clock
        self._ttl = ttl

    def issue(self, account_id: UUID, device_id: UUID) -> str:
        now = _aware_utc(self._clock())
        return jwt.encode(
            {
                "iss": "studyflow-api",
                "aud": "studyflow-client",
                "sub": str(account_id),
                "device_id": str(device_id),
                "type": "access",
                "jti": str(uuid4()),
                "iat": int(now.timestamp()),
                "exp": int((now + self._ttl).timestamp()),
            },
            self._signing_key,
            algorithm="HS256",
        )

    def decode(self, token: str) -> AuthIdentity:
        try:
            claims = jwt.decode(
                token,
                self._signing_key,
                algorithms=["HS256"],
                audience="studyflow-client",
                issuer="studyflow-api",
                options={
                    "require": ["aud", "device_id", "exp", "iat", "iss", "jti", "sub", "type"],
                    "verify_exp": False,
                    "verify_iat": False,
                },
            )
            if claims["type"] != "access":
                raise ValueError("wrong token type")
            now_timestamp = int(_aware_utc(self._clock()).timestamp())
            if int(claims["iat"]) > now_timestamp or int(claims["exp"]) <= now_timestamp:
                raise ValueError("expired token")
            return AuthIdentity(
                account_id=UUID(claims["sub"]),
                device_id=UUID(claims["device_id"]),
            )
        except (jwt.InvalidTokenError, KeyError, TypeError, ValueError) as exc:
            raise AuthServiceError(401, "Invalid or expired access token.") from exc


class AuthService:
    def __init__(
        self,
        session_factory: async_sessionmaker[AsyncSession],
        settings: AuthSettings,
        *,
        clock: Callable[[], datetime] | None = None,
        pairing_code_generator: Callable[[], str] | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._settings = settings
        self._clock = clock or (lambda: datetime.now(UTC))
        self._pairing_code_generator = pairing_code_generator or _random_pairing_code
        self._password_hasher = PasswordHasher(type=Type.ID)
        self._pairing_source_limiter = PairingSourceLimiter(
            settings.token_signing_key,
            attempt_limit=settings.pairing_source_attempt_limit,
            window=settings.pairing_source_window,
            max_sources=settings.pairing_source_cache_size,
        )
        self.access_tokens = AccessTokenCodec(
            settings.token_signing_key,
            clock=self._clock,
            ttl=settings.access_token_ttl,
        )

    def hash_password(self, password: str) -> str:
        return self._password_hasher.hash(password)

    async def bootstrap(
        self,
        *,
        presented_bootstrap_token: str,
        password: str,
        device_id: UUID,
        public_key: str,
        envelope: str,
    ) -> AuthSession:
        if not hmac.compare_digest(
            presented_bootstrap_token.encode("utf-8"),
            self._settings.bootstrap_token.encode("utf-8"),
        ):
            raise AuthServiceError(403, "Bootstrap authorization failed.")

        now = self._now()
        account_id = uuid4()
        try:
            async with self._session_factory() as session:
                async with session.begin():
                    marker = await session.get(BootstrapState, "primary-account")
                    if marker is not None:
                        raise AuthServiceError(409, "Account bootstrap has already completed.")
                    await _set_postgres_context(session, account_id=account_id)
                    if await self._find_device_by_id(session, device_id) is not None:
                        raise AuthServiceError(409, "Device registration is unavailable.")
                    password_hash = await asyncio.to_thread(self.hash_password, password)
                    account = Account(
                        account_id=account_id,
                        password_hash=password_hash,
                    )
                    device = Device(
                        account_id=account_id,
                        device_id=device_id,
                        public_key=public_key,
                        encrypted_account_data_key_envelope=envelope,
                    )
                    session.add_all(
                        [
                            account,
                            device,
                            BootstrapState(
                                state_key="primary-account",
                                account_id=account_id,
                            ),
                        ],
                    )
                    await session.flush()
                    return await self._issue_session(session, device, now)
        except IntegrityError as exc:
            raise AuthServiceError(409, "Account bootstrap has already completed.") from exc

    async def login(self, *, password: str, device_id: UUID) -> AuthSession:
        now = self._now()
        async with self._session_factory() as session:
            async with session.begin():
                await _set_postgres_context(session, device_id=device_id)
                device = await self._find_device_by_id(session, device_id)
                if device is None or device.revoked_at is not None:
                    raise AuthServiceError(401, "Invalid credentials or inactive device.")
                await _set_postgres_context(session, account_id=device.account_id)
                account = await session.get(Account, device.account_id)
                if account is None or account.password_hash is None:
                    raise AuthServiceError(401, "Invalid credentials or inactive device.")
                try:
                    await asyncio.to_thread(
                        self._password_hasher.verify,
                        account.password_hash,
                        password,
                    )
                except (InvalidHashError, VerifyMismatchError) as exc:
                    raise AuthServiceError(401, "Invalid credentials or inactive device.") from exc
                if self._password_hasher.check_needs_rehash(account.password_hash):
                    account.password_hash = await asyncio.to_thread(
                        self.hash_password,
                        password,
                    )
                return await self._issue_session(session, device, now)

    async def refresh(self, refresh_token: str) -> AuthSession:
        now = self._now()
        digest = self._secret_digest(refresh_token, purpose="refresh")
        replacement: AuthSession | None = None
        unauthorized = False
        async with self._session_factory() as session:
            async with session.begin():
                await _set_postgres_context(session, refresh_token_digest=digest)
                refresh_session = await session.scalar(
                    select(RefreshSession)
                    .where(RefreshSession.token_digest == digest)
                    .with_for_update(),
                )
                if refresh_session is None:
                    unauthorized = True
                elif refresh_session.revoked_at is not None:
                    await _set_postgres_context(
                        session,
                        account_id=refresh_session.account_id,
                    )
                    await self._revoke_active_refresh_sessions(
                        session,
                        account_id=refresh_session.account_id,
                        device_id=refresh_session.device_id,
                        revoked_at=now,
                    )
                    unauthorized = True
                elif _aware_utc(refresh_session.expires_at) <= now:
                    unauthorized = True
                else:
                    await _set_postgres_context(session, account_id=refresh_session.account_id)
                    device = await session.get(
                        Device,
                        {
                            "account_id": refresh_session.account_id,
                            "device_id": refresh_session.device_id,
                        },
                    )
                    if device is None or device.revoked_at is not None:
                        await self._revoke_active_refresh_sessions(
                            session,
                            account_id=refresh_session.account_id,
                            device_id=refresh_session.device_id,
                            revoked_at=now,
                        )
                        unauthorized = True
                    else:
                        refresh_session.revoked_at = now
                        replacement = await self._issue_session(session, device, now)
                        replacement_row = await session.scalar(
                            select(RefreshSession)
                            .where(
                                RefreshSession.account_id == device.account_id,
                                RefreshSession.device_id == device.device_id,
                                RefreshSession.token_digest
                                == self._secret_digest(
                                    replacement.refresh_token,
                                    purpose="refresh",
                                ),
                            ),
                        )
                        assert replacement_row is not None
                        refresh_session.replacement_session_id = replacement_row.session_id

        if unauthorized or replacement is None:
            raise AuthServiceError(401, "Invalid or expired refresh token.")
        return replacement

    async def authenticate_access_token(self, token: str) -> AuthIdentity:
        identity = self.access_tokens.decode(token)
        async with self._session_factory() as session:
            await _set_postgres_context(session, account_id=identity.account_id)
            device = await session.get(
                Device,
                {"account_id": identity.account_id, "device_id": identity.device_id},
            )
        if device is None or device.revoked_at is not None:
            raise AuthServiceError(401, "Invalid or inactive device identity.")
        return identity

    async def create_pairing_code(
        self,
        identity: AuthIdentity,
        *,
        target_device_id: UUID,
        target_device_public_key: str,
        envelope: str,
    ) -> CreatedPairingCode:
        now = self._now()
        expires_at = now + self._settings.pairing_code_ttl
        async with self._session_factory() as session:
            async with session.begin():
                await _set_postgres_context(session, device_id=target_device_id)
                if await self._find_device_by_id(session, target_device_id) is not None:
                    raise AuthServiceError(409, "Device registration is unavailable.")
                await _set_postgres_context(session, account_id=identity.account_id)
                source = await session.get(
                    Device,
                    {"account_id": identity.account_id, "device_id": identity.device_id},
                )
                if source is None or source.revoked_at is not None:
                    raise AuthServiceError(401, "Invalid or inactive device identity.")
                code = await self._available_pairing_code(session, now)
                session.add(
                    PairingCode(
                        pairing_id=uuid4(),
                        code_digest=self._secret_digest(code, purpose="pairing"),
                        account_id=identity.account_id,
                        source_device_id=identity.device_id,
                        target_device_id=target_device_id,
                        target_device_public_key=target_device_public_key,
                        encrypted_account_data_key_envelope=envelope,
                        expires_at=expires_at,
                    ),
                )
        return CreatedPairingCode(code=code, expires_at=expires_at)

    async def pair(
        self,
        *,
        code: str,
        device_id: UUID,
        device_public_key: str,
        source: str,
    ) -> AuthSession:
        now = self._now()
        if not await self._pairing_source_limiter.consume(source, now):
            raise _pairing_denied()
        digest = self._secret_digest(code, purpose="pairing")
        authenticated: AuthSession | None = None
        denied = False
        async with self._session_factory() as session:
            async with session.begin():
                await _set_postgres_context(
                    session,
                    device_id=device_id,
                    device_public_key=device_public_key,
                    pairing_code_digest=digest,
                )
                target_matches = and_(
                    PairingCode.target_device_id == device_id,
                    PairingCode.target_device_public_key == device_public_key,
                )
                pairing = await session.scalar(
                    select(PairingCode)
                    .where(
                        or_(
                            PairingCode.code_digest == digest,
                            target_matches,
                        ),
                    )
                    .order_by(
                        case((target_matches, 0), else_=1),
                        PairingCode.created_at.desc(),
                        PairingCode.pairing_id.desc(),
                    )
                    .limit(1)
                    .with_for_update(),
                )
                if (
                    pairing is None
                    or pairing.consumed_at is not None
                    or _aware_utc(pairing.expires_at) <= now
                    or pairing.failed_attempts >= self._settings.pairing_code_attempt_limit
                ):
                    denied = True
                elif (
                    not hmac.compare_digest(pairing.code_digest, digest)
                    or pairing.target_device_id != device_id
                    or not hmac.compare_digest(
                        pairing.target_device_public_key,
                        device_public_key,
                    )
                ):
                    await _set_postgres_context(session, account_id=pairing.account_id)
                    pairing.failed_attempts += 1
                    if pairing.failed_attempts >= self._settings.pairing_code_attempt_limit:
                        pairing.consumed_at = now
                    denied = True
                else:
                    await _set_postgres_context(session, device_id=device_id)
                    if await self._find_device_by_id(session, device_id) is not None:
                        raise AuthServiceError(409, "Device registration is unavailable.")
                    await _set_postgres_context(session, account_id=pairing.account_id)
                    device = Device(
                        account_id=pairing.account_id,
                        device_id=device_id,
                        public_key=device_public_key,
                        encrypted_account_data_key_envelope=(
                            pairing.encrypted_account_data_key_envelope
                        ),
                    )
                    session.add(device)
                    pairing.consumed_at = now
                    await session.flush()
                    authenticated = await self._issue_session(session, device, now)

        if denied or authenticated is None:
            raise _pairing_denied()
        return authenticated

    async def revoke_device(self, identity: AuthIdentity, device_id: UUID) -> None:
        now = self._now()
        async with self._session_factory() as session:
            async with session.begin():
                await _set_postgres_context(session, account_id=identity.account_id)
                device = await session.get(
                    Device,
                    {"account_id": identity.account_id, "device_id": device_id},
                )
                if device is None:
                    raise AuthServiceError(404, "Device was not found in this account.")
                if device.revoked_at is None:
                    device.revoked_at = now
                await session.execute(
                    update(RefreshSession)
                    .where(
                        RefreshSession.account_id == identity.account_id,
                        RefreshSession.device_id == device_id,
                        RefreshSession.revoked_at.is_(None),
                    )
                    .values(revoked_at=now),
                )

    async def _issue_session(
        self,
        session: AsyncSession,
        device: Device,
        now: datetime,
    ) -> AuthSession:
        envelope = device.encrypted_account_data_key_envelope
        if envelope is None:
            raise AuthServiceError(401, "Device enrollment is incomplete.")
        refresh_token = f"sfr_{secrets.token_urlsafe(48)}"
        session.add(
            RefreshSession(
                session_id=uuid4(),
                account_id=device.account_id,
                device_id=device.device_id,
                token_digest=self._secret_digest(refresh_token, purpose="refresh"),
                expires_at=now + self._settings.refresh_token_ttl,
            ),
        )
        await session.flush()
        return AuthSession(
            account_id=device.account_id,
            device_id=device.device_id,
            access_token=self.access_tokens.issue(device.account_id, device.device_id),
            refresh_token=refresh_token,
            expires_in=int(self._settings.access_token_ttl.total_seconds()),
            encrypted_account_data_key_envelope=envelope,
        )

    async def _revoke_active_refresh_sessions(
        self,
        session: AsyncSession,
        *,
        account_id: UUID,
        device_id: UUID,
        revoked_at: datetime,
    ) -> None:
        await session.execute(
            update(RefreshSession)
            .where(
                RefreshSession.account_id == account_id,
                RefreshSession.device_id == device_id,
                RefreshSession.revoked_at.is_(None),
            )
            .values(revoked_at=revoked_at),
        )

    async def _available_pairing_code(
        self,
        session: AsyncSession,
        now: datetime,
    ) -> str:
        for _ in range(20):
            code = self._pairing_code_generator()
            if len(code) != 6 or not code.isdigit():
                raise RuntimeError("Pairing code generator must return six digits.")
            active = await session.scalar(
                select(PairingCode.pairing_id).where(
                    PairingCode.code_digest
                    == self._secret_digest(code, purpose="pairing"),
                    PairingCode.consumed_at.is_(None),
                    PairingCode.expires_at > now,
                ),
            )
            if active is None:
                return code
        raise AuthServiceError(503, "A pairing code could not be allocated.")

    async def _find_device_by_id(
        self,
        session: AsyncSession,
        device_id: UUID,
    ) -> Device | None:
        return await session.scalar(select(Device).where(Device.device_id == device_id))

    def _secret_digest(self, value: str, *, purpose: str) -> bytes:
        return hmac.new(
            self._settings.token_signing_key.encode("utf-8"),
            f"{purpose}\x00{value}".encode("utf-8"),
            sha256,
        ).digest()

    def _now(self) -> datetime:
        return _aware_utc(self._clock())


async def _set_postgres_context(
    session: AsyncSession,
    *,
    account_id: UUID | None = None,
    device_id: UUID | None = None,
    device_public_key: str | None = None,
    refresh_token_digest: bytes | None = None,
    pairing_code_digest: bytes | None = None,
) -> None:
    bind = session.get_bind()
    if bind.dialect.name != "postgresql":
        return
    if account_id is not None:
        await session.execute(
            text("SELECT set_config('app.account_id', :account_id, true)"),
            {"account_id": str(account_id)},
        )
    if device_id is not None:
        await session.execute(
            text("SELECT set_config('app.device_id', :device_id, true)"),
            {"device_id": str(device_id)},
        )
    if device_public_key is not None:
        await session.execute(
            text(
                "SELECT set_config('app.device_public_key', "
                ":device_public_key, true)",
            ),
            {"device_public_key": device_public_key},
        )
    if refresh_token_digest is not None:
        await session.execute(
            text(
                "SELECT set_config('app.refresh_token_digest', "
                ":refresh_token_digest, true)",
            ),
            {"refresh_token_digest": refresh_token_digest.hex()},
        )
    if pairing_code_digest is not None:
        await session.execute(
            text(
                "SELECT set_config('app.pairing_code_digest', "
                ":pairing_code_digest, true)",
            ),
            {"pairing_code_digest": pairing_code_digest.hex()},
        )


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def _random_pairing_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def _pairing_denied() -> AuthServiceError:
    return AuthServiceError(410, "Pairing request denied.")
