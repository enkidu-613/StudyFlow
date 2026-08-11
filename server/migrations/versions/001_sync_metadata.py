"""create sync metadata tables and rls

Revision ID: 001_sync_metadata
Revises:
Create Date: 2026-08-11 08:30:00
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "001_sync_metadata"
down_revision = None
branch_labels = None
depends_on = None


ACCOUNT_ID_RLS_EXPRESSION = "NULLIF(current_setting('app.account_id', true), '')::uuid"


def upgrade() -> None:
    op.create_table(
        "accounts",
        sa.Column("account_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("timezone('utc', now())"),
        ),
        sa.PrimaryKeyConstraint("account_id"),
    )

    op.create_table(
        "devices",
        sa.Column("account_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("device_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("timezone('utc', now())"),
        ),
        sa.ForeignKeyConstraint(["account_id"], ["accounts.account_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("account_id", "device_id", name="pk_devices"),
        sa.UniqueConstraint("device_id", name="uq_devices_device_id"),
    )
    op.create_index("ix_devices_account_id", "devices", ["account_id"], unique=False)

    op.create_table(
        "sync_operations",
        sa.Column(
            "server_sequence",
            sa.BigInteger(),
            sa.Identity(always=False),
            nullable=False,
        ),
        sa.Column("account_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("device_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("operation_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("record_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("payload_nonce", sa.LargeBinary(), nullable=False),
        sa.Column("payload_ciphertext", sa.LargeBinary(), nullable=False),
        sa.Column("is_tombstone", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("timezone('utc', now())"),
        ),
        sa.ForeignKeyConstraint(["account_id"], ["accounts.account_id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["account_id", "device_id"],
            ["devices.account_id", "devices.device_id"],
            ondelete="CASCADE",
            name="fk_sync_operations_account_device",
        ),
        sa.PrimaryKeyConstraint("server_sequence"),
        sa.UniqueConstraint("account_id", "operation_id", name="uq_sync_operations_account_operation"),
    )
    op.create_index(
        "ix_sync_operations_account_id",
        "sync_operations",
        ["account_id"],
        unique=False,
    )
    op.create_index(
        "ix_sync_operations_account_server_sequence",
        "sync_operations",
        ["account_id", "server_sequence"],
        unique=False,
    )

    for table_name in ("accounts", "devices", "sync_operations"):
        op.execute(sa.text(f"ALTER TABLE {table_name} ENABLE ROW LEVEL SECURITY"))
        op.execute(sa.text(f"ALTER TABLE {table_name} FORCE ROW LEVEL SECURITY"))

    op.execute(
        sa.text(
            f"""
            CREATE POLICY accounts_select_policy ON accounts
            FOR SELECT
            USING (account_id = {ACCOUNT_ID_RLS_EXPRESSION})
            """,
        ),
    )
    op.execute(
        sa.text(
            f"""
            CREATE POLICY accounts_insert_policy ON accounts
            FOR INSERT
            WITH CHECK (account_id = {ACCOUNT_ID_RLS_EXPRESSION})
            """,
        ),
    )

    for table_name in ("devices", "sync_operations"):
        op.execute(
            sa.text(
                f"""
                CREATE POLICY {table_name}_select_policy ON {table_name}
                FOR SELECT
                USING (account_id = {ACCOUNT_ID_RLS_EXPRESSION})
                """,
            ),
        )
        op.execute(
            sa.text(
                f"""
                CREATE POLICY {table_name}_insert_policy ON {table_name}
                FOR INSERT
                WITH CHECK (account_id = {ACCOUNT_ID_RLS_EXPRESSION})
                """,
            ),
        )


def downgrade() -> None:
    for table_name in ("sync_operations", "devices", "accounts"):
        op.execute(sa.text(f"DROP POLICY IF EXISTS {table_name}_select_policy ON {table_name}"))
        op.execute(sa.text(f"DROP POLICY IF EXISTS {table_name}_insert_policy ON {table_name}"))
    op.execute(sa.text("DROP POLICY IF EXISTS accounts_select_policy ON accounts"))
    op.execute(sa.text("DROP POLICY IF EXISTS accounts_insert_policy ON accounts"))

    op.drop_index("ix_sync_operations_account_server_sequence", table_name="sync_operations")
    op.drop_index("ix_sync_operations_account_id", table_name="sync_operations")
    op.drop_table("sync_operations")
    op.drop_index("ix_devices_account_id", table_name="devices")
    op.drop_table("devices")
    op.drop_table("accounts")
