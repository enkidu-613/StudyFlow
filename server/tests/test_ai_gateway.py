from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import UUID

import pytest

from server.app.ai.models import (
    AiInputSummary,
    AiRecommendationDraft,
    CandidateScheduleChange,
)
from server.app.ai.provider import (
    AiProviderUnavailableError,
    UnconfiguredAiProvider,
)
from server.app.ai.redaction import build_prompt
from server.app.ai.service import (
    AiPolicyError,
    AiService,
    MemoryAiAuditStore,
    ensure_no_direct_writes,
)
from server.app.ai import models as ai_models


ACCOUNT_ID = UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")


class FakeAiProvider:
    """Test provider that records the exact prompt it received."""

    provider_id = "fake"
    model_id = "fake-model-v1"

    def __init__(self, draft: AiRecommendationDraft | None = None) -> None:
        self.draft = draft or AiRecommendationDraft(
            summary="Focus on the morning study block.",
            candidate_changes=[],
            reason_codes=["morning_focus"],
            confidence=0.6,
        )
        self.last_input: AiInputSummary | None = None
        self.last_prompt: str | None = None

    async def generate_plan(self, summary: AiInputSummary) -> AiRecommendationDraft:
        self.last_input = summary
        self.last_prompt = build_prompt(summary)
        return self.draft


@pytest.fixture
def fake_provider() -> FakeAiProvider:
    return FakeAiProvider()


def summary_with_sensitive_fields() -> AiInputSummary:
    """A summary carrying raw activity fields and a secret alongside the
    whitelist fields. The redaction boundary must strip the sensitive ones."""
    payload = {
        "permissionLevel": "L1",
        "taskIds": ["bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"],
        "taskTitles": ["Read chapter 1"],
        "scheduleMetrics": {"overlap_count": 0},
        "focusCompletionMetrics": {"completion_rate": 0.8},
        "sleepAggregates": {"avg_sleep_minutes": 430},
        # Attempted smuggled fields: raw activity, browsing data, and secrets.
        "window_title": "YouTube - study break",
        "raw_browser_url": "https://example.com/watch?v=abc",
        "service_role": "sb_secret_service_role_key",
    }
    return AiInputSummary(**payload)


async def generate_recommendation(
    summary: AiInputSummary,
    provider: FakeAiProvider,
    *,
    now: datetime | None = None,
) -> ai_models.AiRecommendation:
    audit_store = MemoryAiAuditStore()
    service = AiService(provider=provider, audit_store=audit_store)
    return await service.generate_recommendation(
        account_id=ACCOUNT_ID,
        summary=summary,
        now=now,
    )


@pytest.mark.anyio
async def test_ai_input_excludes_raw_activity_and_secrets(
    fake_provider: FakeAiProvider,
) -> None:
    await generate_recommendation(summary_with_sensitive_fields(), fake_provider)

    prompt = fake_provider.last_prompt
    assert prompt is not None
    assert "window_title" not in prompt
    assert "raw_browser_url" not in prompt
    assert "service_role" not in prompt
    assert "Read chapter 1" in prompt


@pytest.mark.anyio
async def test_whitelist_fields_survive_redaction(fake_provider: FakeAiProvider) -> None:
    summary = summary_with_sensitive_fields()
    await generate_recommendation(summary, fake_provider)

    prompt = fake_provider.last_prompt
    assert "permissionLevel" in prompt
    assert "scheduleMetrics" in prompt
    assert "sleepAggregates" in prompt


@pytest.mark.anyio
async def test_l1_recommendation_requires_confirmation(
    fake_provider: FakeAiProvider,
) -> None:
    recommendation = await generate_recommendation(
        summary_with_sensitive_fields(),
        fake_provider,
    )

    assert recommendation.permission_level == "L1"
    assert recommendation.requires_confirmation is True
    assert recommendation.candidate_changes == []


@pytest.mark.anyio
async def test_l2_changes_require_confirmation_even_with_provider_changes(
    fake_provider: FakeAiProvider,
) -> None:
    fake_provider.draft = AiRecommendationDraft(
        summary="Shift the rest block.",
        candidate_changes=[
            CandidateScheduleChange(
                action="shift_schedule_block",
                blockId="cccccccc-cccc-4ccc-8ccc-cccccccccccc",
                deltaMinutes=15,
                reason="Align with sleep window.",
            )
        ],
        reason_codes=["rest_alignment"],
        confidence=0.7,
    )
    summary = summary_with_sensitive_fields()
    summary = summary.model_copy(update={"permission_level": "L2"})

    recommendation = await generate_recommendation(summary, fake_provider)

    assert recommendation.requires_confirmation is True
    assert len(recommendation.candidate_changes) == 1


@pytest.mark.anyio
async def test_l3_is_rejected_without_authorization(
    fake_provider: FakeAiProvider,
) -> None:
    summary = summary_with_sensitive_fields()
    summary = summary.model_copy(
        update={
            "permission_level": "L3",
            "focus_completion_metrics": {"consecutive_valid_days": 20},
        }
    )
    now = datetime.now(timezone.utc)

    with pytest.raises(AiPolicyError) as exc_info:
        await generate_recommendation(summary, fake_provider, now=now)

    assert exc_info.value.status_code == 403


@pytest.mark.anyio
async def test_l3_is_allowed_with_prior_grant_and_14_days(
    fake_provider: FakeAiProvider,
) -> None:
    now = datetime.now(timezone.utc)
    audit_store = MemoryAiAuditStore()
    # Simulate a fresh explicit L3 authorization recorded earlier.
    await audit_store.record(
        account_id=ACCOUNT_ID,
        recommendation=ai_models.AiRecommendation(
            recommendationId=UUID("dddddddd-dddd-4ddd-8ddd-dddddddddddd"),
            accountId=ACCOUNT_ID,
            permissionLevel="L3",
            providerId="fake",
            modelId="fake-model-v1",
            summary="Explicit L3 authorization.",
            candidateChanges=[],
            reasonCodes=["explicit_authorization"],
            confidence=1.0,
            requiresConfirmation=False,
            createdAt=now - timedelta(days=1),
        ),
    )
    service = AiService(provider=fake_provider, audit_store=audit_store)
    summary = summary_with_sensitive_fields()
    summary = summary.model_copy(
        update={
            "permission_level": "L3",
            "focus_completion_metrics": {"consecutive_valid_days": 14},
        }
    )

    recommendation = await service.generate_recommendation(
        account_id=ACCOUNT_ID,
        summary=summary,
        now=now,
    )

    assert recommendation.permission_level == "L3"


@pytest.mark.anyio
async def test_l3_grant_expires_after_max_age(
    fake_provider: FakeAiProvider,
) -> None:
    now = datetime.now(timezone.utc)
    audit_store = MemoryAiAuditStore()
    await audit_store.record(
        account_id=ACCOUNT_ID,
        recommendation=ai_models.AiRecommendation(
            recommendationId=UUID("dddddddd-dddd-4ddd-8ddd-dddddddddddd"),
            accountId=ACCOUNT_ID,
            permissionLevel="L3",
            providerId="fake",
            modelId="fake-model-v1",
            summary="Old explicit L3 authorization.",
            candidateChanges=[],
            reasonCodes=["explicit_authorization"],
            confidence=1.0,
            requiresConfirmation=False,
            createdAt=now - timedelta(days=31),
        ),
    )
    service = AiService(provider=fake_provider, audit_store=audit_store)
    summary = summary_with_sensitive_fields()
    summary = summary.model_copy(
        update={
            "permission_level": "L3",
            "focus_completion_metrics": {"consecutive_valid_days": 14},
        }
    )

    with pytest.raises(AiPolicyError) as exc_info:
        await service.generate_recommendation(account_id=ACCOUNT_ID, summary=summary, now=now)

    assert exc_info.value.status_code == 403


@pytest.mark.anyio
async def test_ai_service_cannot_write_repositories(fake_provider: FakeAiProvider) -> None:
    audit_store = MemoryAiAuditStore()
    service = AiService(provider=fake_provider, audit_store=audit_store)

    ensure_no_direct_writes(service)
    assert not hasattr(service, "task_repository")
    assert not hasattr(service, "schedule_repository")


@pytest.mark.anyio
async def test_unconfigured_provider_returns_503() -> None:
    audit_store = MemoryAiAuditStore()
    service = AiService(provider=UnconfiguredAiProvider(), audit_store=audit_store)

    with pytest.raises(AiPolicyError) as exc_info:
        await service.generate_recommendation(
            account_id=ACCOUNT_ID,
            summary=summary_with_sensitive_fields(),
        )

    assert exc_info.value.status_code == 503
    assert isinstance(exc_info.value.detail, str)


@pytest.mark.anyio
async def test_unknown_recommendation_action_is_rejected() -> None:
    with pytest.raises(Exception) as exc_info:
        CandidateScheduleChange(
            action="delete_all_schedule",
            blockId="cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            deltaMinutes=0,
        )
    assert "unsupported recommendation action" in str(exc_info.value)


def test_provider_unavailable_error_is_explicit() -> None:
    with pytest.raises(AiProviderUnavailableError):
        raise AiProviderUnavailableError("No AI provider is configured.")


def test_recommendations_endpoint_requires_authentication() -> None:
    from fastapi import Depends, FastAPI
    from fastapi.testclient import TestClient

    from server.app.ai.routes import get_ai_service, router as ai_router
    from server.app.ai.service import AiService
    from server.app.auth.dependencies import get_account_context
    from server.app.db.context import AccountContext

    def deny_context() -> AccountContext:
        from fastapi import HTTPException, status

        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Bearer access token is required.",
        )

    probe_app = FastAPI()
    probe_app.include_router(ai_router)
    probe_app.dependency_overrides[get_account_context] = deny_context
    probe_app.dependency_overrides[get_ai_service] = lambda: AiService(
        provider=FakeAiProvider(),
        audit_store=MemoryAiAuditStore(),
    )

    client = TestClient(probe_app)
    response = client.post(
        "/v1/ai/recommendations",
        json={
            "summary": {
                "permissionLevel": "L1",
                "taskIds": [],
                "taskTitles": ["Read chapter 1"],
                "scheduleMetrics": {},
                "focusCompletionMetrics": {},
                "sleepAggregates": {},
            }
        },
    )

    assert response.status_code == 401
