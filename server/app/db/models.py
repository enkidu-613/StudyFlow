from __future__ import annotations

from datetime import datetime
from uuid import UUID

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    ForeignKey,
    ForeignKeyConstraint,
    Identity,
    Index,
    Integer,
    LargeBinary,
    PrimaryKeyConstraint,
    String,
    Text,
    Uuid,
    UniqueConstraint,
    func,
)
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
            "entity_type IN ('task', 'schedule_block', 'focus_session', 'check_in')",
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
