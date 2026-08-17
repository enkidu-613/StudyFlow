"""allow medication plan and dose record sync entities

Revision ID: 008_medication_entities
Revises: 007_schedule_feedback_entity
Create Date: 2026-08-17 00:00:00
"""

from __future__ import annotations

from alembic import op


revision = "008_medication_entities"
down_revision = "007_schedule_feedback_entity"
branch_labels = None
depends_on = None

_OLD_TYPES = (
    "entity_type IN ('task', 'schedule_block', 'focus_session', 'check_in', "
    "'schedule_feedback')"
)
_NEW_TYPES = (
    "entity_type IN ('task', 'schedule_block', 'focus_session', 'check_in', "
    "'schedule_feedback', 'medication_plan', 'medication_dose_record')"
)


def _replace_constraint(table: str, constraint: str, expression: str) -> None:
    op.drop_constraint(constraint, table, type_="check")
    op.create_check_constraint(constraint, table, expression)


def upgrade() -> None:
    _replace_constraint("user_sync_operations", "ck_user_sync_operations_entity_type", _NEW_TYPES)
    _replace_constraint("sync_operations", "ck_sync_operations_entity_type", _NEW_TYPES)


def downgrade() -> None:
    _replace_constraint("user_sync_operations", "ck_user_sync_operations_entity_type", _OLD_TYPES)
    _replace_constraint("sync_operations", "ck_sync_operations_entity_type", _OLD_TYPES)
