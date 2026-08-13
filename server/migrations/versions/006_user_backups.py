"""create per-user backups

Revision ID: 006_user_backups
Revises: 005_plaintext_sync_operations
Create Date: 2026-08-13 00:00:00
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "006_user_backups"
down_revision = "005_plaintext_sync_operations"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_backups",
        sa.Column("backup_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(length=64), nullable=False),
        sa.Column("payload", postgresql.JSONB(), nullable=False),
        sa.Column("size_bytes", sa.BigInteger(), nullable=False),
        sa.Column("operation_count", sa.Integer(), nullable=False),
        sa.Column("last_operation_sequence", sa.BigInteger(), nullable=False, server_default=sa.text("0")),
        sa.Column(
            "status",
            sa.String(length=16),
            nullable=False,
            server_default=sa.text("'ready'"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("timezone('utc', now())"),
        ),
        sa.CheckConstraint(
            "length(name) > 0 AND name NOT LIKE ' %' AND name NOT LIKE '% '",
            name="ck_user_backups_name_nonempty",
        ),
        sa.CheckConstraint(
            "status IN ('creating', 'ready', 'failed')",
            name="ck_user_backups_status",
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.user_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("backup_id"),
    )
    op.create_index(
        "ix_user_backups_user_id",
        "user_backups",
        ["user_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_user_backups_user_id", table_name="user_backups")
    op.drop_table("user_backups")
