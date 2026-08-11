from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "002_auth_devices"
down_revision = "001_sync_metadata"
branch_labels = None
depends_on = None


ACCOUNT_ID_RLS_EXPRESSION = "NULLIF(current_setting('app.account_id', true), '')::uuid"
DEVICE_ID_RLS_EXPRESSION = "NULLIF(current_setting('app.device_id', true), '')::uuid"


def upgrade() -> None:
    op.add_column("accounts", sa.Column("password_hash", sa.String(length=512), nullable=True))
    op.add_column("devices", sa.Column("public_key", sa.Text(), nullable=True))
    op.add_column(
        "devices",
        sa.Column("encrypted_account_data_key_envelope", sa.Text(), nullable=True),
    )
    op.add_column(
        "devices",
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
    )

    op.create_table(
        "auth_bootstrap_state",
        sa.Column("state_key", sa.String(length=64), nullable=False),
        sa.Column("account_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("timezone('utc', now())"),
        ),
        sa.ForeignKeyConstraint(["account_id"], ["accounts.account_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("state_key"),
        sa.UniqueConstraint("account_id"),
    )
    op.create_table(
        "auth_refresh_sessions",
        sa.Column("session_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("account_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("device_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("token_digest", sa.LargeBinary(length=32), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("replacement_session_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("timezone('utc', now())"),
        ),
        sa.ForeignKeyConstraint(
            ["account_id", "device_id"],
            ["devices.account_id", "devices.device_id"],
            ondelete="CASCADE",
            name="fk_refresh_sessions_account_device",
        ),
        sa.PrimaryKeyConstraint("session_id"),
        sa.UniqueConstraint("token_digest"),
    )
    op.create_index(
        "ix_refresh_sessions_account_device",
        "auth_refresh_sessions",
        ["account_id", "device_id"],
    )
    op.create_table(
        "auth_pairing_codes",
        sa.Column("pairing_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("code_digest", sa.LargeBinary(length=32), nullable=False),
        sa.Column("account_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("source_device_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("target_device_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("target_device_public_key", sa.Text(), nullable=False),
        sa.Column("encrypted_account_data_key_envelope", sa.Text(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("timezone('utc', now())"),
        ),
        sa.ForeignKeyConstraint(
            ["account_id", "source_device_id"],
            ["devices.account_id", "devices.device_id"],
            ondelete="CASCADE",
            name="fk_pairing_codes_source_device",
        ),
        sa.PrimaryKeyConstraint("pairing_id"),
    )
    op.create_index("ix_pairing_codes_digest", "auth_pairing_codes", ["code_digest"])
    op.create_index("ix_pairing_codes_account", "auth_pairing_codes", ["account_id"])

    op.execute(
        sa.text(
            f"""
            CREATE POLICY devices_auth_lookup_policy ON devices
            FOR SELECT
            USING (device_id = {DEVICE_ID_RLS_EXPRESSION})
            """,
        ),
    )
    op.execute(
        sa.text(
            f"""
            CREATE POLICY devices_update_policy ON devices
            FOR UPDATE
            USING (account_id = {ACCOUNT_ID_RLS_EXPRESSION})
            WITH CHECK (account_id = {ACCOUNT_ID_RLS_EXPRESSION})
            """,
        ),
    )


def downgrade() -> None:
    op.execute(sa.text("DROP POLICY IF EXISTS devices_update_policy ON devices"))
    op.execute(sa.text("DROP POLICY IF EXISTS devices_auth_lookup_policy ON devices"))
    op.drop_index("ix_pairing_codes_account", table_name="auth_pairing_codes")
    op.drop_index("ix_pairing_codes_digest", table_name="auth_pairing_codes")
    op.drop_table("auth_pairing_codes")
    op.drop_index("ix_refresh_sessions_account_device", table_name="auth_refresh_sessions")
    op.drop_table("auth_refresh_sessions")
    op.drop_table("auth_bootstrap_state")
    op.drop_column("devices", "revoked_at")
    op.drop_column("devices", "encrypted_account_data_key_envelope")
    op.drop_column("devices", "public_key")
    op.drop_column("accounts", "password_hash")
