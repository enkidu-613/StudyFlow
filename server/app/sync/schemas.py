from __future__ import annotations

import base64
import binascii
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator


EntityType = Literal["task", "schedule_block", "focus_session", "check_in"]
MAX_PAYLOAD_BYTES = 256 * 1024


def _decode_base64(value: object, field_name: str) -> bytes:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{field_name} must be a non-empty base64 string")
    try:
        decoded = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ValueError(f"{field_name} must be valid base64") from exc
    if base64.b64encode(decoded).decode("ascii") != value:
        raise ValueError(f"{field_name} must use canonical base64")
    return decoded


def _validate_uuid(value: object, field_name: str) -> UUID:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{field_name} must be a non-empty UUID")
    try:
        return UUID(value)
    except ValueError as exc:
        raise ValueError(f"{field_name} must be a valid UUID") from exc


class SyncOperationV1(BaseModel):
    model_config = ConfigDict(
        alias_generator=None,
        extra="forbid",
        populate_by_name=True,
    )

    operation_id: UUID = Field(alias="operationId")
    record_id: UUID = Field(alias="recordId")
    device_id: UUID = Field(alias="deviceId")
    logical_clock: int = Field(alias="logicalClock", ge=0)
    entity_type: EntityType = Field(alias="entityType")
    payload_nonce: bytes = Field(alias="payloadNonce", min_length=1)
    payload_ciphertext: bytes = Field(alias="payloadCiphertext", min_length=1)
    is_tombstone: bool = Field(alias="isTombstone")
    schema_version: Literal[1] = Field(alias="schemaVersion")

    @field_validator("operation_id", "record_id", "device_id", mode="before")
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

    @field_validator("payload_nonce", "payload_ciphertext", mode="before")
    @classmethod
    def validate_payload_encoding(cls, value: object, info) -> bytes:
        decoded = _decode_base64(value, info.field_name)
        if len(decoded) > MAX_PAYLOAD_BYTES:
            raise ValueError(f"{info.field_name} must be at most 256 KiB")
        return decoded

    @field_serializer("payload_nonce", "payload_ciphertext")
    def serialize_payload(self, value: bytes) -> str:
        return base64.b64encode(value).decode("ascii")


class SyncPushRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    operations: list[SyncOperationV1]


class SyncPushResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    accepted: list[UUID]
    duplicates: list[UUID]
    rejected: list[UUID]


class SyncPullResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    next_cursor: Annotated[int, Field(ge=0)]
    operations: list[SyncOperationV1]


class SyncPullQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    after: Annotated[int, Field(ge=0)] = 0
    limit: Annotated[int, Field(ge=1, le=200)] = 50
