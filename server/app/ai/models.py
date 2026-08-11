from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

PermissionLevel = Literal["L0", "L1", "L2", "L3"]

RECOMMENDATION_ACTIONS = frozenset(
    {
        "adjust_sleep_window",
        "shift_schedule_block",
        "suggest_rest_block",
        "suggest_focus_block",
    }
)


class AiInputSummary(BaseModel):
    """Structured data received from the client.

    Only the declared whitelist fields survive the redaction boundary in
    ``server.app.ai.redaction.build_prompt``. Extra fields (window titles,
    raw URLs, secrets) are accepted so smuggling attempts are observable, but
    they never reach an AI provider.
    """

    model_config = ConfigDict(extra="allow", populate_by_name=True)

    permission_level: PermissionLevel = Field(alias="permissionLevel", default="L1")
    task_ids: list[UUID] = Field(alias="taskIds", default_factory=list)
    task_titles: list[str] = Field(alias="taskTitles", default_factory=list)
    schedule_metrics: dict[str, float] = Field(
        alias="scheduleMetrics", default_factory=dict
    )
    focus_completion_metrics: dict[str, float] = Field(
        alias="focusCompletionMetrics", default_factory=dict
    )
    sleep_aggregates: dict[str, float] = Field(
        alias="sleepAggregates", default_factory=dict
    )

    @field_validator("task_titles")
    @classmethod
    def limit_task_title_length(cls, value: list[str]) -> list[str]:
        return [title[:200] for title in value]


class CandidateScheduleChange(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    action: str
    block_id: UUID = Field(alias="blockId")
    delta_minutes: int = Field(alias="deltaMinutes", ge=-24 * 60, le=24 * 60)
    reason: str = Field(default="", max_length=500)

    @field_validator("action")
    @classmethod
    def require_supported_action(cls, value: str) -> str:
        if value not in RECOMMENDATION_ACTIONS:
            raise ValueError(f"unsupported recommendation action: {value}")
        return value


class AiRecommendationDraft(BaseModel):
    """Structured output expected from an AI provider.

    This model is the only shape a provider may return; arbitrary model text
    is rejected before it can influence the schedule.
    """

    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    summary: str = Field(max_length=2000)
    candidate_changes: list[CandidateScheduleChange] = Field(
        alias="candidateChanges", default_factory=list
    )
    reason_codes: list[str] = Field(alias="reasonCodes", default_factory=list)
    confidence: float = Field(ge=0.0, le=1.0, default=0.5)


class AiRecommendation(BaseModel):
    """A validated recommendation that never mutates tasks or schedule blocks."""

    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    recommendation_id: UUID = Field(alias="recommendationId")
    account_id: UUID = Field(alias="accountId")
    permission_level: PermissionLevel = Field(alias="permissionLevel")
    provider_id: str = Field(alias="providerId")
    model_id: str = Field(alias="modelId")
    summary: str = Field(max_length=2000)
    candidate_changes: list[CandidateScheduleChange] = Field(
        alias="candidateChanges", default_factory=list
    )
    reason_codes: list[str] = Field(alias="reasonCodes", default_factory=list)
    confidence: float = Field(ge=0.0, le=1.0)
    requires_confirmation: bool = Field(alias="requiresConfirmation", default=True)
    created_at: datetime = Field(alias="createdAt")


class AiRecommendationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    summary: AiInputSummary


class AiRecommendationResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    recommendation: AiRecommendation
