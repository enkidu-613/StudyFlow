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
DEVICE_PUBLIC_KEY_RLS_EXPRESSION = (
    "NULLIF(current_setting('app.device_public_key', true), '')"
)
REFRESH_DIGEST_RLS_EXPRESSION = (
    "decode(NULLIF(current_setting('app.refresh_token_digest', true), ''), 'hex')"
)
PAIRING_DIGEST_RLS_EXPRESSION = (
    "decode(NULLIF(current_setting('app.pairing_code_digest', true), ''), 'hex')"
)


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
            "failed_attempts",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
        ),
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

    for table_name in (
        "auth_bootstrap_state",
        "auth_refresh_sessions",
        "auth_pairing_codes",
    ):
        op.execute(sa.text(f"ALTER TABLE {table_name} ENABLE ROW LEVEL SECURITY"))
        op.execute(sa.text(f"ALTER TABLE {table_name} FORCE ROW LEVEL SECURITY"))

    op.execute(
        sa.text(
            """
            CREATE POLICY auth_bootstrap_state_select_policy ON auth_bootstrap_state
            FOR SELECT
            USING (state_key = 'primary-account')
            """,
        ),
    )
    op.execute(
        sa.text(
            f"""
            CREATE POLICY auth_bootstrap_state_insert_policy ON auth_bootstrap_state
            FOR INSERT
            WITH CHECK (
                state_key = 'primary-account'
                AND account_id = {ACCOUNT_ID_RLS_EXPRESSION}
            )
            """,
        ),
    )
    op.execute(
        sa.text(
            f"""
            CREATE POLICY auth_refresh_sessions_select_policy ON auth_refresh_sessions
            FOR SELECT
            USING (
                account_id = {ACCOUNT_ID_RLS_EXPRESSION}
                OR token_digest = {REFRESH_DIGEST_RLS_EXPRESSION}
            )
            """,
        ),
    )
    op.execute(
        sa.text(
            f"""
            CREATE POLICY auth_refresh_sessions_insert_policy ON auth_refresh_sessions
            FOR INSERT
            WITH CHECK (account_id = {ACCOUNT_ID_RLS_EXPRESSION})
            """,
        ),
    )
    op.execute(
        sa.text(
            f"""
            CREATE POLICY auth_refresh_sessions_update_policy ON auth_refresh_sessions
            FOR UPDATE
            USING (account_id = {ACCOUNT_ID_RLS_EXPRESSION})
            WITH CHECK (account_id = {ACCOUNT_ID_RLS_EXPRESSION})
            """,
        ),
    )
    op.execute(
        sa.text(
            f"""
            CREATE POLICY auth_pairing_codes_select_policy ON auth_pairing_codes
            FOR SELECT
            USING (
                account_id = {ACCOUNT_ID_RLS_EXPRESSION}
                OR code_digest = {PAIRING_DIGEST_RLS_EXPRESSION}
                OR (
                    target_device_id = {DEVICE_ID_RLS_EXPRESSION}
                    AND target_device_public_key = {DEVICE_PUBLIC_KEY_RLS_EXPRESSION}
                )
            )
            """,
        ),
    )
    op.execute(
        sa.text(
            f"""
            CREATE POLICY auth_pairing_codes_insert_policy ON auth_pairing_codes
            FOR INSERT
            WITH CHECK (account_id = {ACCOUNT_ID_RLS_EXPRESSION})
            """,
        ),
    )
    op.execute(
        sa.text(
            f"""
            CREATE POLICY auth_pairing_codes_update_policy ON auth_pairing_codes
            FOR UPDATE
            USING (account_id = {ACCOUNT_ID_RLS_EXPRESSION})
            WITH CHECK (account_id = {ACCOUNT_ID_RLS_EXPRESSION})
            """,
        ),
    )

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
            CREATE POLICY accounts_update_policy ON accounts
            FOR UPDATE
            USING (account_id = {ACCOUNT_ID_RLS_EXPRESSION})
            WITH CHECK (account_id = {ACCOUNT_ID_RLS_EXPRESSION})
            """,
        ),
    )

    op.execute(
        sa.text(
            """
            DO $$
            DECLARE
                data_api_role text;
                protected_table text;
            BEGIN
                FOREACH data_api_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role']
                LOOP
                    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = data_api_role) THEN
                        FOREACH protected_table IN ARRAY ARRAY[
                            'accounts',
                            'devices',
                            'sync_operations',
                            'auth_bootstrap_state',
                            'auth_refresh_sessions',
                            'auth_pairing_codes'
                        ]
                        LOOP
                            EXECUTE format(
                                'REVOKE ALL PRIVILEGES ON TABLE public.%I FROM %I',
                                protected_table,
                                data_api_role
                            );
                        END LOOP;
                    END IF;
                END LOOP;
            END
            $$
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
    op.execute(sa.text("DROP POLICY IF EXISTS accounts_update_policy ON accounts"))
    op.execute(sa.text("DROP POLICY IF EXISTS devices_update_policy ON devices"))
    op.execute(sa.text("DROP POLICY IF EXISTS devices_auth_lookup_policy ON devices"))
    for policy_name, table_name in (
        ("auth_pairing_codes_update_policy", "auth_pairing_codes"),
        ("auth_pairing_codes_insert_policy", "auth_pairing_codes"),
        ("auth_pairing_codes_select_policy", "auth_pairing_codes"),
        ("auth_refresh_sessions_update_policy", "auth_refresh_sessions"),
        ("auth_refresh_sessions_insert_policy", "auth_refresh_sessions"),
        ("auth_refresh_sessions_select_policy", "auth_refresh_sessions"),
        ("auth_bootstrap_state_insert_policy", "auth_bootstrap_state"),
        ("auth_bootstrap_state_select_policy", "auth_bootstrap_state"),
    ):
        op.execute(sa.text(f"DROP POLICY IF EXISTS {policy_name} ON {table_name}"))
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
