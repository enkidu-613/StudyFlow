from __future__ import annotations

from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


EntityType = Literal["task", "schedule_block", "focus_session", "check_in"]
MAX_PAYLOAD_BYTES = 256 * 1024


class SyncOperationV2(BaseModel):
    model_config = ConfigDict(
        alias_generator=None,
        extra="forbid",
        populate_by_name=True,
    )

    operation_id: UUID = Field(alias="operationId")
    record_id: UUID = Field(alias="recordId")
    logical_clock: int = Field(alias="logicalClock", ge=0)
    entity_type: EntityType = Field(alias="entityType")
    payload: dict[str, object] = Field(alias="payload")
    is_tombstone: bool = Field(alias="isTombstone")
    schema_version: Literal[1] = Field(alias="schemaVersion")

    @field_validator("operation_id", "record_id", mode="before")
    @classmethod
    def validate_ids(cls, value: object, info) -> UUID:
        return _validate_uuid(value, info.field_name)

    @field_validator("logical_clock", "schema_version", mode="before")
    @classmethod
    def validate_integer_fields(cls, value: object, info) -> int:
        if isinstance(value, bool) or not isinstance(value, int):
            raise ValueError(f"{info.field_name} must be an integer")
        return value

    @field_validator("is_tombstone", mode="before")
    @classmethod
    def validate_tombstone(cls, value: object) -> bool:
        if not isinstance(value, bool):
            raise ValueError("is_tombstone must be a boolean")
        return value

    @field_validator("payload")
    @classmethod
    def validate_payload_type(cls, value: object) -> dict[str, object]:
        if not isinstance(value, dict):
            raise ValueError("payload must be a JSON object")
        return value

    @model_validator(mode="after")
    def validate_payload_nonempty(self) -> SyncOperationV2:
        if not self.payload and self.is_tombstone is not True:
            raise ValueError("payload must not be empty for non-tombstone operations")
        return self


def _validate_uuid(value: object, field_name: str) -> UUID:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{field_name} must be a non-empty UUID")
    try:
        return UUID(value)
    except ValueError as exc:
        raise ValueError(f"{field_name} must be a valid UUID") from exc


class SyncPushRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    operations: list[SyncOperationV2]


class SyncPushResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    accepted: list[UUID]
    duplicates: list[UUID]
    rejected: list[UUID]


class SyncPullResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    next_cursor: Annotated[int, Field(ge=0)]
    operations: list[SyncOperationV2]


class SyncPullQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    after: Annotated[int, Field(ge=0)] = 0
    limit: Annotated[int, Field(ge=1, le=200)] = 50
