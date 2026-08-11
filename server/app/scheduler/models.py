from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

ScheduleBlockKind = Literal["task", "rest", "sleep", "breakTime"]
ScheduleBlockSource = Literal["manual", "generated", "imported"]

TARGET_WAKE_TIME_PATTERN = r"^([01]\d|2[0-3]):[0-5]\d([+-]([01]\d|2[0-3]):[0-5]\d)?$"
TIMEZONE_OFFSET_PATTERN = r"^[+-]([01]\d|2[0-3]):[0-5]\d$"


class ScheduleBlock(BaseModel):
    """A schedule block in UTC, mirroring the client domain model wire format."""

    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    id: UUID
    start: datetime
    end: datetime
    kind: ScheduleBlockKind
    task_id: Annotated[UUID | None, Field(alias="taskId")] = None
    source: ScheduleBlockSource
    is_locked: bool = Field(alias="isLocked")

    @field_validator("start", "end")
    @classmethod
    def require_utc(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("start/end must carry a timezone (UTC)")
        return value

    @field_validator("end")
    @classmethod
    def require_end_after_start(cls, value: datetime, info) -> datetime:
        start = info.data.get("start")
        if start is not None and not value > start:
            raise ValueError("end must be after start")
        return value


class CheckInSummary(BaseModel):
    """Minimal validated check-in fields used by the schedule policy."""

    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    recorded_at: datetime = Field(alias="recordedAt")
    sleep_minutes: int = Field(alias="sleepMinutes", ge=0, le=24 * 60)
    sleep_quality: int = Field(alias="sleepQuality", ge=1, le=5)
    energy: int = Field(ge=1, le=5)
    mood: int = Field(ge=1, le=5)


class SleepProfile(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    age_range: str = Field(alias="ageRange", min_length=1, max_length=32)
    timezone_offset: str = Field(alias="timezoneOffset", pattern=TIMEZONE_OFFSET_PATTERN)
    target_wake_time: str = Field(alias="targetWakeTime", pattern=TARGET_WAKE_TIME_PATTERN)
    target_sleep_duration_minutes: int = Field(
        alias="targetSleepDurationMinutes",
        ge=240,
        le=720,
    )
    adjustment_step_minutes: int = Field(
        alias="adjustmentStepMinutes",
        ge=15,
        le=30,
        default=15,
    )
    minimum_rest_minutes: int = Field(
        alias="minimumRestMinutes",
        ge=0,
        le=24 * 60,
        default=60,
    )


class ScheduleProposal(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    proposal_id: UUID = Field(alias="proposalId")
    original_blocks: list[ScheduleBlock] = Field(alias="originalBlocks")
    candidate_blocks: list[ScheduleBlock] = Field(alias="candidateBlocks")
    reason_codes: list[str] = Field(alias="reasonCodes")
    requires_confirmation: bool = Field(alias="requiresConfirmation")
    sleep_start_delta_minutes: int = Field(alias="sleepStartDeltaMinutes")
    created_at: datetime = Field(alias="createdAt")


class ValidateScheduleProposalRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    profile: SleepProfile
    history: list[CheckInSummary]
    existing_blocks: list[ScheduleBlock]


class ValidateScheduleProposalResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    proposal: ScheduleProposal
