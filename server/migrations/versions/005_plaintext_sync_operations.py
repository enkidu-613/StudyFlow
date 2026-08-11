"""create plaintext JSONB sync operations

Revision ID: 005_plaintext_sync_operations
Revises: 004_local_email_auth
Create Date: 2026-08-12 00:00:00
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "005_plaintext_sync_operations"
down_revision = "004_local_email_auth"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_sync_operations",
        sa.Column(
            "server_sequence",
            sa.BigInteger(),
            sa.Identity(always=False),
            nullable=False,
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("operation_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("record_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("logical_clock", sa.BigInteger(), nullable=False),
        sa.Column("entity_type", sa.String(length=32), nullable=False),
        sa.Column("payload", postgresql.JSONB(), nullable=False),
        sa.Column("is_tombstone", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("schema_version", sa.Integer(), nullable=False, server_default=sa.text("1")),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("timezone('utc', now())"),
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.user_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("server_sequence"),
        sa.UniqueConstraint(
            "user_id",
            "operation_id",
            name="uq_user_sync_operations_user_operation",
        ),
        sa.CheckConstraint(
            "logical_clock >= 0",
            name="ck_user_sync_operations_logical_clock_nonnegative",
        ),
        sa.CheckConstraint(
            "entity_type IN ('task', 'schedule_block', 'focus_session', 'check_in')",
            name="ck_user_sync_operations_entity_type",
        ),
        sa.CheckConstraint(
            "schema_version = 1",
            name="ck_user_sync_operations_schema_version",
        ),
    )
    op.create_index(
        "ix_user_sync_operations_user_id",
        "user_sync_operations",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_sync_operations_user_sequence",
        "user_sync_operations",
        ["user_id", "server_sequence"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_user_sync_operations_user_sequence",
        table_name="user_sync_operations",
    )
    op.drop_index(
        "ix_user_sync_operations_user_id",
        table_name="user_sync_operations",
    )
    op.drop_table("user_sync_operations")
