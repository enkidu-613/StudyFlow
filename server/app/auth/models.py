from __future__ import annotations

import base64
import binascii
import hmac
from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, SecretStr, field_validator
from cryptography.hazmat.primitives.asymmetric.x25519 import (
    X25519PrivateKey,
    X25519PublicKey,
)
from sqlalchemy import (
    DateTime,
    ForeignKey,
    ForeignKeyConstraint,
    Index,
    Integer,
    LargeBinary,
    String,
    Text,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from server.app.db.models import Account, Base, Device, TimestampedModel


OpaqueBase64 = Annotated[str, Field(min_length=4, max_length=65_536)]


def _canonical_base64(value: str) -> str:
    try:
        decoded = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ValueError("must be canonical base64") from exc
    if not decoded or base64.b64encode(decoded).decode("ascii") != value:
        raise ValueError("must be canonical base64")
    return value


def _x25519_public_key(value: str) -> str:
    value = _canonical_base64(value)
    public_key_bytes = base64.b64decode(value)
    if len(public_key_bytes) != 32:
        raise ValueError("must contain a 32-byte X25519 public key")
    try:
        shared_secret = X25519PrivateKey.generate().exchange(
            X25519PublicKey.from_public_bytes(public_key_bytes),
        )
    except ValueError as exc:
        raise ValueError("must contain a valid X25519 public key") from exc
    if hmac.compare_digest(shared_secret, bytes(32)):
        raise ValueError("must not derive an all-zero X25519 shared secret")
    return value


class BootstrapState(TimestampedModel, Base):
    __tablename__ = "auth_bootstrap_state"

    state_key: Mapped[str] = mapped_column(String(64), primary_key=True)
    account_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("accounts.account_id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )


class RefreshSession(TimestampedModel, Base):
    __tablename__ = "auth_refresh_sessions"
    __table_args__ = (
        ForeignKeyConstraint(
            ["account_id", "device_id"],
            ["devices.account_id", "devices.device_id"],
            ondelete="CASCADE",
            name="fk_refresh_sessions_account_device",
        ),
        Index("ix_refresh_sessions_account_device", "account_id", "device_id"),
    )

    session_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    account_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    device_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    token_digest: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False, unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    replacement_session_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)


class PairingCode(TimestampedModel, Base):
    __tablename__ = "auth_pairing_codes"
    __table_args__ = (
        ForeignKeyConstraint(
            ["account_id", "source_device_id"],
            ["devices.account_id", "devices.device_id"],
            ondelete="CASCADE",
            name="fk_pairing_codes_source_device",
        ),
        Index("ix_pairing_codes_digest", "code_digest"),
        Index("ix_pairing_codes_account", "account_id"),
    )

    pairing_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    code_digest: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    account_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    source_device_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    target_device_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    target_device_public_key: Mapped[str] = mapped_column(Text, nullable=False)
    encrypted_account_data_key_envelope: Mapped[str] = mapped_column(Text, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    failed_attempts: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default="0",
    )


class StrictRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    @field_validator("*", mode="before")
    @classmethod
    def reject_nul_strings(cls, value: object) -> object:
        if isinstance(value, str) and "\x00" in value:
            raise ValueError("NUL bytes are not allowed")
        return value


class BootstrapRequest(StrictRequest):
    password: SecretStr = Field(min_length=12, max_length=256)
    device_id: UUID
    device_public_key: OpaqueBase64
    encrypted_account_data_key_envelope: OpaqueBase64

    _validate_public_key = field_validator("device_public_key")(_x25519_public_key)
    _validate_envelope = field_validator("encrypted_account_data_key_envelope")(
        _canonical_base64,
    )


class LoginRequest(StrictRequest):
    password: SecretStr = Field(min_length=1, max_length=256)
    device_id: UUID


class RefreshRequest(StrictRequest):
    refresh_token: SecretStr = Field(min_length=32, max_length=512)


class CreatePairingCodeRequest(StrictRequest):
    target_device_id: UUID
    target_device_public_key: OpaqueBase64
    encrypted_account_data_key_envelope: OpaqueBase64

    _validate_public_key = field_validator("target_device_public_key")(_x25519_public_key)
    _validate_envelope = field_validator("encrypted_account_data_key_envelope")(
        _canonical_base64,
    )


class PairDeviceRequest(StrictRequest):
    code: str = Field(pattern=r"^[0-9]{6}$")
    device_id: UUID
    device_public_key: OpaqueBase64

    _validate_public_key = field_validator("device_public_key")(_x25519_public_key)


class RevokeDeviceRequest(StrictRequest):
    device_id: UUID


class AuthResponse(BaseModel):
    account_id: UUID
    device_id: UUID
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int
    encrypted_account_data_key_envelope: str


class PairingCodeResponse(BaseModel):
    code: str
    expires_at: datetime


class SessionResponse(BaseModel):
    account_id: UUID
    device_id: UUID


__all__ = [
    "Account",
    "AuthResponse",
    "BootstrapRequest",
    "BootstrapState",
    "CreatePairingCodeRequest",
    "Device",
    "LoginRequest",
    "PairDeviceRequest",
    "PairingCode",
    "PairingCodeResponse",
    "RefreshRequest",
    "RefreshSession",
    "RevokeDeviceRequest",
    "SessionResponse",
]
