from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "003_sync_operation_contract"
down_revision = "002_auth_devices"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "sync_operations",
        sa.Column(
            "logical_clock",
            sa.BigInteger(),
            nullable=False,
            server_default=sa.text("0"),
        ),
    )
    op.add_column(
        "sync_operations",
        sa.Column(
            "entity_type",
            sa.String(length=32),
            nullable=False,
            server_default=sa.text("'task'"),
        ),
    )
    op.add_column(
        "sync_operations",
        sa.Column(
            "schema_version",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("1"),
        ),
    )
    op.create_check_constraint(
        "ck_sync_operations_logical_clock_nonnegative",
        "sync_operations",
        "logical_clock >= 0",
    )
    op.create_check_constraint(
        "ck_sync_operations_entity_type",
        "sync_operations",
        "entity_type IN ('task', 'schedule_block', 'focus_session', 'check_in')",
    )
    op.create_check_constraint(
        "ck_sync_operations_schema_version",
        "sync_operations",
        "schema_version = 1",
    )
    op.alter_column("sync_operations", "logical_clock", server_default=None)
    op.alter_column("sync_operations", "entity_type", server_default=None)
    op.alter_column("sync_operations", "schema_version", server_default=None)


def downgrade() -> None:
    op.drop_constraint(
        "ck_sync_operations_schema_version",
        "sync_operations",
        type_="check",
    )
    op.drop_constraint(
        "ck_sync_operations_entity_type",
        "sync_operations",
        type_="check",
    )
    op.drop_constraint(
        "ck_sync_operations_logical_clock_nonnegative",
        "sync_operations",
        type_="check",
    )
    op.drop_column("sync_operations", "schema_version")
    op.drop_column("sync_operations", "entity_type")
    op.drop_column("sync_operations", "logical_clock")
