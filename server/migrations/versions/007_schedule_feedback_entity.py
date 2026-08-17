"""allow schedule completion feedback sync entities

Revision ID: 007_schedule_feedback_entity
Revises: 006_user_backups
Create Date: 2026-08-17 00:00:00
"""

from __future__ import annotations

from alembic import op


revision = "007_schedule_feedback_entity"
down_revision = "006_user_backups"
branch_labels = None
depends_on = None

_OLD_TYPES = "entity_type IN ('task', 'schedule_block', 'focus_session', 'check_in')"
_NEW_TYPES = (
    "entity_type IN ('task', 'schedule_block', 'focus_session', 'check_in', "
    "'schedule_feedback')"
)


def upgrade() -> None:
    op.drop_constraint(
        "ck_user_sync_operations_entity_type",
        "user_sync_operations",
        type_="check",
    )
    op.create_check_constraint(
        "ck_user_sync_operations_entity_type",
        "user_sync_operations",
        _NEW_TYPES,
    )
    op.drop_constraint(
        "ck_sync_operations_entity_type",
        "sync_operations",
        type_="check",
    )
    op.create_check_constraint(
        "ck_sync_operations_entity_type",
        "sync_operations",
        _NEW_TYPES,
    )


def downgrade() -> None:
    op.drop_constraint(
        "ck_user_sync_operations_entity_type",
        "user_sync_operations",
        type_="check",
    )
    op.create_check_constraint(
        "ck_user_sync_operations_entity_type",
        "user_sync_operations",
        _OLD_TYPES,
    )
    op.drop_constraint(
        "ck_sync_operations_entity_type",
        "sync_operations",
        type_="check",
    )
    op.create_check_constraint(
        "ck_sync_operations_entity_type",
        "sync_operations",
        _OLD_TYPES,
    )
