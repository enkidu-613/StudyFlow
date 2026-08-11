from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Protocol
from uuid import UUID, uuid4

from server.app.ai.models import (
    AiInputSummary,
    AiRecommendation,
    AiRecommendationDraft,
)
from server.app.ai.provider import AiProvider, AiProviderUnavailableError
from server.app.ai.redaction import build_prompt

# L3 requires at least this many consecutive valid days of records and a fresh
# explicit authorization before automatic schedule mutation can be considered.
L3_MIN_CONSECUTIVE_DAYS = 14
L3_AUTHORIZATION_MAX_AGE = timedelta(days=30)


class AiPolicyError(RuntimeError):
    def __init__(self, status_code: int, detail: str) -> None:
        self.status_code = status_code
        self.detail = detail
        super().__init__(detail)


class AiAuditStore(Protocol):
    """Persists only a redacted audit summary of each recommendation."""

    async def record(
        self,
        *,
        account_id: UUID,
        recommendation: AiRecommendation,
    ) -> None: ...


class MemoryAiAuditStore:
    """In-memory audit store for tests and single-process development."""

    def __init__(self) -> None:
        self.records: list[tuple[UUID, AiRecommendation]] = []

    async def record(
        self,
        *,
        account_id: UUID,
        recommendation: AiRecommendation,
    ) -> None:
        self.records.append((account_id, recommendation))


class AiAuthorization(Protocol):
    """Access policy for recommendation levels."""

    async def l3_eligible(
        self,
        account_id: UUID,
        *,
        consecutive_valid_days: int,
        now: datetime,
    ) -> bool: ...


class DefaultAiAuthorization:
    """L3 eligibility requires 14+ consecutive valid days and a fresh grant.

    A grant is represented by an entry in the audit store whose permission
    level is L3 and whose created_at is newer than the configured max age.
    """

    def __init__(self, audit_store: AiAuditStore) -> None:
        self._audit_store = audit_store

    async def l3_eligible(
        self,
        account_id: UUID,
        *,
        consecutive_valid_days: int,
        now: datetime,
    ) -> bool:
        if consecutive_valid_days < L3_MIN_CONSECUTIVE_DAYS:
            return False
        if not isinstance(self._audit_store, MemoryAiAuditStore):
            return False
        return any(
            stored_account_id == account_id
            and record.permission_level == "L3"
            and record.created_at >= now - L3_AUTHORIZATION_MAX_AGE
            for stored_account_id, record in self._audit_store.records
        )


@dataclass(frozen=True, slots=True)
class AiServiceSettings:
    require_confirmation_for_changes: bool = True


class AiService:
    """Generates privacy-bounded recommendations.

    The service never writes tasks or schedule blocks. It validates the
    provider draft, enforces the L0-L3 permission ladder, and persists only a
    redacted audit record.
    """

    def __init__(
        self,
        *,
        provider: AiProvider,
        audit_store: AiAuditStore,
        authorization: AiAuthorization | None = None,
        settings: AiServiceSettings = AiServiceSettings(),
    ) -> None:
        self._provider = provider
        self._audit_store = audit_store
        self._authorization = authorization or DefaultAiAuthorization(audit_store)
        self._settings = settings

    async def generate_recommendation(
        self,
        *,
        account_id: UUID,
        summary: AiInputSummary,
        now: datetime | None = None,
    ) -> AiRecommendation:
        created_at = now or datetime.now(timezone.utc)
        await self._enforce_level(account_id, summary, created_at)

        try:
            draft = await self._provider.generate_plan(summary)
        except AiProviderUnavailableError as exc:
            raise AiPolicyError(503, exc.args[0]) from exc

        requires_confirmation = self._settings.require_confirmation_for_changes
        if summary.permission_level == "L1":
            requires_confirmation = True

        recommendation = AiRecommendation(
            recommendation_id=uuid4(),
            account_id=account_id,
            permission_level=summary.permission_level,
            provider_id=self._provider.provider_id,
            model_id=self._provider.model_id,
            summary=draft.summary,
            candidate_changes=draft.candidate_changes,
            reason_codes=draft.reason_codes,
            confidence=draft.confidence,
            requires_confirmation=requires_confirmation,
            created_at=created_at,
        )
        await self._audit_store.record(account_id=account_id, recommendation=recommendation)
        return recommendation

    async def _enforce_level(
        self,
        account_id: UUID,
        summary: AiInputSummary,
        now: datetime,
    ) -> None:
        level = summary.permission_level
        if level in ("L0", "L1", "L2"):
            return
        if level == "L3":
            eligible = await self._authorization.l3_eligible(
                account_id,
                consecutive_valid_days=summary.focus_completion_metrics.get(
                    "consecutive_valid_days",
                    0,
                ),
                now=now,
            )
            if not eligible:
                raise AiPolicyError(
                    403,
                    "L3 requires at least 14 consecutive valid days and a "
                    "fresh explicit authorization.",
                )
            return
        raise AiPolicyError(403, f"Unknown permission level: {level}")


def ensure_no_direct_writes(service: AiService) -> None:
    """Guard used by tests: the AI service must not expose repository writes.

    The service only depends on a provider and an audit store; it holds no
    task or schedule repository references by construction.
    """
    assert not hasattr(service, "task_repository")
    assert not hasattr(service, "schedule_repository")
