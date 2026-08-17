from __future__ import annotations

from datetime import datetime
from uuid import UUID

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    ForeignKeyConstraint,
    Identity,
    Index,
    Integer,
    JSON,
    LargeBinary,
    PrimaryKeyConstraint,
    String,
    Text,
    UniqueConstraint,
    Uuid,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class TimestampedModel:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )


class Account(TimestampedModel, Base):
    __tablename__ = "accounts"

    account_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    password_hash: Mapped[str | None] = mapped_column(String(512), nullable=True)


class Device(TimestampedModel, Base):
    __tablename__ = "devices"
    __table_args__ = (
        PrimaryKeyConstraint("account_id", "device_id", name="pk_devices"),
        UniqueConstraint("device_id", name="uq_devices_device_id"),
    )

    account_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("accounts.account_id", ondelete="CASCADE"),
        primary_key=True,
        nullable=False,
    )
    device_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
    )
    public_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    encrypted_account_data_key_envelope: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
    )
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class SyncOperation(TimestampedModel, Base):
    __tablename__ = "sync_operations"
    __table_args__ = (
        UniqueConstraint("account_id", "operation_id", name="uq_sync_operations_account_operation"),
        Index("ix_sync_operations_account_server_sequence", "account_id", "server_sequence"),
        CheckConstraint(
            "logical_clock >= 0",
            name="ck_sync_operations_logical_clock_nonnegative",
        ),
        CheckConstraint(
            "entity_type IN ('task', 'schedule_block', 'focus_session', 'check_in', "
            "'schedule_feedback', 'medication_plan', 'medication_dose_record')",
            name="ck_sync_operations_entity_type",
        ),
        CheckConstraint(
            "schema_version = 1",
            name="ck_sync_operations_schema_version",
        ),
        ForeignKeyConstraint(
            ["account_id", "device_id"],
            ["devices.account_id", "devices.device_id"],
            ondelete="CASCADE",
            name="fk_sync_operations_account_device",
        ),
    )

    server_sequence: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        Identity(always=False),
        primary_key=True,
    )
    account_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("accounts.account_id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    device_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        nullable=False,
    )
    operation_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    record_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    logical_clock: Mapped[int] = mapped_column(BigInteger, nullable=False)
    entity_type: Mapped[str] = mapped_column(String(32), nullable=False)
    payload_nonce: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    payload_ciphertext: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    is_tombstone: Mapped[bool] = mapped_column(
        nullable=False,
        default=False,
        server_default="false",
    )
    schema_version: Mapped[int] = mapped_column(Integer, nullable=False)


class User(TimestampedModel, Base):
    __tablename__ = "users"
    __table_args__ = (
        UniqueConstraint("email_normalized", name="uq_users_email_normalized"),
        Index("ix_users_email_normalized", "email_normalized"),
    )

    user_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    email: Mapped[str] = mapped_column(String(320), nullable=False)
    email_normalized: Mapped[str] = mapped_column(String(320), nullable=False)
    password_hash: Mapped[str] = mapped_column(String(512), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )


class UserSession(TimestampedModel, Base):
    __tablename__ = "user_sessions"
    __table_args__ = (
        UniqueConstraint("token_digest", name="uq_user_sessions_token_digest"),
        Index("ix_user_sessions_user_id", "user_id"),
    )

    session_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.user_id", ondelete="CASCADE"),
        nullable=False,
    )
    token_digest: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    replacement_session_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)


class UserSyncOperation(TimestampedModel, Base):
    __tablename__ = "user_sync_operations"
    __table_args__ = (
        UniqueConstraint("user_id", "operation_id", name="uq_user_sync_operations_user_operation"),
        Index("ix_user_sync_operations_user_sequence", "user_id", "server_sequence"),
        CheckConstraint(
            "logical_clock >= 0",
            name="ck_user_sync_operations_logical_clock_nonnegative",
        ),
        CheckConstraint(
            "entity_type IN ('task', 'schedule_block', 'focus_session', 'check_in', "
            "'schedule_feedback', 'medication_plan', 'medication_dose_record')",
            name="ck_user_sync_operations_entity_type",
        ),
        CheckConstraint(
            "schema_version = 1",
            name="ck_user_sync_operations_schema_version",
        ),
    )

    server_sequence: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        Identity(always=False),
        primary_key=True,
    )
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.user_id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    operation_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    record_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    logical_clock: Mapped[int] = mapped_column(BigInteger, nullable=False)
    entity_type: Mapped[str] = mapped_column(String(32), nullable=False)
    payload: Mapped[dict] = mapped_column(
        JSON().with_variant(JSONB, "postgresql"),
        nullable=False,
    )
    is_tombstone: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="false",
    )
    schema_version: Mapped[int] = mapped_column(Integer, nullable=False)


class UserBackup(TimestampedModel, Base):
    __tablename__ = "user_backups"
    __table_args__ = (
        CheckConstraint(
            "length(name) > 0 AND name NOT LIKE ' %' AND name NOT LIKE '% '",
            name="ck_user_backups_name_nonempty",
        ),
        CheckConstraint(
            "status IN ('creating', 'ready', 'failed')",
            name="ck_user_backups_status",
        ),
    )

    backup_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.user_id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(64), nullable=False)
    payload: Mapped[dict] = mapped_column(
        JSON().with_variant(JSONB, "postgresql"),
        nullable=False,
    )
    size_bytes: Mapped[int] = mapped_column(BigInteger, nullable=False)
    operation_count: Mapped[int] = mapped_column(Integer, nullable=False)
    last_operation_sequence: Mapped[int] = mapped_column(
        BigInteger,
        nullable=False,
        default=0,
        server_default="0",
    )
    status: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default="ready",
        server_default="ready",
    )
