from __future__ import annotations

import asyncio
import hmac
import os
import secrets
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from hashlib import sha256
from uuid import UUID, uuid4

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError
from argon2.low_level import Type
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from server.app.auth.models import RegisterRequest
from server.app.auth.password_policy import normalize_email, validate_password
from server.app.db.context import UserContext
from server.app.db.models import User, UserSession


@dataclass(frozen=True, slots=True)
class AuthSettings:
    token_signing_key: str
    access_token_ttl: timedelta = timedelta(minutes=15)
    refresh_token_ttl: timedelta = timedelta(days=30)

    @classmethod
    def from_env(cls) -> AuthSettings:
        token_signing_key = os.getenv("STUDYFLOW_TOKEN_SIGNING_KEY")
        if not token_signing_key:
            raise ValueError("STUDYFLOW_TOKEN_SIGNING_KEY must be set")
        if len(token_signing_key.encode("utf-8")) < 32:
            raise ValueError("STUDYFLOW_TOKEN_SIGNING_KEY must contain at least 32 bytes")
        return cls(token_signing_key=token_signing_key)


@dataclass(frozen=True, slots=True)
class AuthSession:
    user_id: UUID
    email: str
    access_token: str
    refresh_token: str
    expires_in: int


class AuthServiceError(RuntimeError):
    def __init__(self, status_code: int, detail: str) -> None:
        self.status_code = status_code
        self.detail = detail
        super().__init__(detail)


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

    def issue(self, user_id: UUID, email: str) -> str:
        now = _aware_utc(self._clock())
        return jwt.encode(
            {
                "iss": "studyflow-api",
                "aud": "studyflow-client",
                "sub": str(user_id),
                "email": email,
                "type": "access",
                "jti": str(uuid4()),
                "iat": int(now.timestamp()),
                "exp": int((now + self._ttl).timestamp()),
            },
            self._signing_key,
            algorithm="HS256",
        )

    def decode(self, token: str) -> UserContext:
        try:
            claims = jwt.decode(
                token,
                self._signing_key,
                algorithms=["HS256"],
                audience="studyflow-client",
                issuer="studyflow-api",
                options={
                    "require": ["aud", "exp", "iat", "iss", "jti", "sub", "type"],
                    "verify_exp": False,
                    "verify_iat": False,
                },
            )
            if claims["type"] != "access":
                raise ValueError("wrong token type")
            now_timestamp = int(_aware_utc(self._clock()).timestamp())
            if int(claims["iat"]) > now_timestamp or int(claims["exp"]) <= now_timestamp:
                raise ValueError("expired token")
            return UserContext(
                user_id=UUID(claims["sub"]),
                email=str(claims["email"]),
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
    ) -> None:
        self._session_factory = session_factory
        self._settings = settings
        self._clock = clock or (lambda: datetime.now(UTC))
        self._password_hasher = PasswordHasher(type=Type.ID)
        self.access_tokens = AccessTokenCodec(
            settings.token_signing_key,
            clock=self._clock,
            ttl=settings.access_token_ttl,
        )

    def hash_password(self, password: str) -> str:
        return self._password_hasher.hash(password)

    async def register(self, request: RegisterRequest) -> AuthSession:
        email = normalize_email(request.email)
        validate_password(request.password)
        password_hash = await asyncio.to_thread(self.hash_password, request.password)
        user = User(
            user_id=uuid4(),
            email=request.email.strip(),
            email_normalized=email,
            password_hash=password_hash,
        )
        try:
            async with self._session_factory() as session:
                async with session.begin():
                    session.add(user)
                    await session.flush()
                    return await self._issue_session(session, user)
        except IntegrityError as exc:
            raise AuthServiceError(
                409,
                "An account with this email already exists.",
            ) from exc

    async def login(self, *, email: str, password: str) -> AuthSession:
        email_normalized = normalize_email(email)
        async with self._session_factory() as session:
            async with session.begin():
                user = await session.scalar(
                    select(User).where(User.email_normalized == email_normalized),
                )
                if user is None:
                    raise AuthServiceError(401, "Invalid credentials.")
                try:
                    await asyncio.to_thread(
                        self._password_hasher.verify,
                        user.password_hash,
                        password,
                    )
                except (InvalidHashError, VerifyMismatchError) as exc:
                    raise AuthServiceError(401, "Invalid credentials.") from exc
                if self._password_hasher.check_needs_rehash(user.password_hash):
                    user.password_hash = await asyncio.to_thread(
                        self.hash_password,
                        password,
                    )
                return await self._issue_session(session, user)

    async def refresh(self, refresh_token: str) -> AuthSession:
        now = self._now()
        digest = self._secret_digest(refresh_token, purpose="refresh")
        replacement: AuthSession | None = None
        unauthorized = False
        async with self._session_factory() as session:
            async with session.begin():
                refresh_session = await session.scalar(
                    select(UserSession)
                    .where(UserSession.token_digest == digest)
                    .with_for_update(),
                )
                if refresh_session is None:
                    unauthorized = True
                elif refresh_session.revoked_at is not None:
                    await self._revoke_replaced_chain(session, refresh_session)
                    unauthorized = True
                elif _aware_utc(refresh_session.expires_at) <= now:
                    unauthorized = True
                else:
                    user = await session.get(User, refresh_session.user_id)
                    if user is None:
                        unauthorized = True
                    else:
                        refresh_session.revoked_at = now
                        replacement = await self._issue_session(session, user)
                        replacement_row = await session.scalar(
                            select(UserSession).where(
                                UserSession.user_id == user.user_id,
                                UserSession.token_digest
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

    async def logout(self, refresh_token: str) -> None:
        now = self._now()
        digest = self._secret_digest(refresh_token, purpose="refresh")
        async with self._session_factory() as session:
            async with session.begin():
                refresh_session = await session.scalar(
                    select(UserSession)
                    .where(UserSession.token_digest == digest)
                    .with_for_update(),
                )
                if refresh_session is None:
                    raise AuthServiceError(401, "Invalid refresh token.")
                if refresh_session.revoked_at is None:
                    refresh_session.revoked_at = now

    async def authenticate_access_token(self, token: str) -> UserContext:
        identity = self.access_tokens.decode(token)
        async with self._session_factory() as session:
            user = await session.get(User, identity.user_id)
        if user is None:
            raise AuthServiceError(401, "Invalid or expired access token.")
        return identity

    async def _issue_session(
        self,
        session: AsyncSession,
        user: User,
    ) -> AuthSession:
        refresh_token = f"sfr_{secrets.token_urlsafe(48)}"
        session.add(
            UserSession(
                session_id=uuid4(),
                user_id=user.user_id,
                token_digest=self._secret_digest(refresh_token, purpose="refresh"),
                expires_at=self._now() + self._settings.refresh_token_ttl,
            ),
        )
        await session.flush()
        return AuthSession(
            user_id=user.user_id,
            email=user.email,
            access_token=self.access_tokens.issue(user.user_id, user.email),
            refresh_token=refresh_token,
            expires_in=int(self._settings.access_token_ttl.total_seconds()),
        )

    async def _revoke_replaced_chain(
        self,
        session: AsyncSession,
        refresh_session: UserSession,
    ) -> None:
        revoked_at = self._now()
        seen: set[UUID] = set()
        current_id: UUID | None = refresh_session.session_id
        while current_id is not None and current_id not in seen:
            seen.add(current_id)
            row = await session.scalar(
                select(UserSession).where(UserSession.session_id == current_id),
            )
            if row is None:
                break
            row.revoked_at = revoked_at
            current_id = row.replacement_session_id

    def _secret_digest(self, value: str, *, purpose: str) -> bytes:
        return hmac.new(
            self._settings.token_signing_key.encode("utf-8"),
            f"{purpose}\x00{value}".encode("utf-8"),
            sha256,
        ).digest()

    def _now(self) -> datetime:
        return _aware_utc(self._clock())


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)
