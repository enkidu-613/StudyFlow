from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from server.app.auth.models import StrictRequest


def _validate_backup_name(value: str) -> str:
    if not isinstance(value, str):
        raise ValueError("name must be a string")
    trimmed = value.strip()
    if not trimmed:
        raise ValueError("name must not be empty after trimming")
    if len(trimmed) > 64:
        raise ValueError("name must be at most 64 characters")
    if "\x00" in trimmed:
        raise ValueError("NUL bytes are not allowed")
    return trimmed


class CreateBackupRequest(StrictRequest):
    name: str | None = None

    @field_validator("name")
    @classmethod
    def validate_optional_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return _validate_backup_name(value)


class RenameBackupRequest(StrictRequest):
    name: str

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        return _validate_backup_name(value)


class BatchDeleteBackupRequest(StrictRequest):
    backup_ids: list[UUID] = Field(min_length=1)

    @field_validator("backup_ids")
    @classmethod
    def validate_unique_ids(cls, value: list[UUID]) -> list[UUID]:
        if len(set(value)) != len(value):
            raise ValueError("backup_ids must not contain duplicates")
        return value


class BatchDeleteResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    deleted: int
    not_found: list[UUID]


class BackupSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    backup_id: UUID
    name: str
    created_at: datetime
    size_bytes: int
    operation_count: int
    status: Literal["creating", "ready", "failed"]


class BackupListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    backups: list[BackupSummary]
