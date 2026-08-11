from __future__ import annotations

from typing import Protocol

from server.app.ai.models import AiInputSummary, AiRecommendationDraft


class AiProvider(Protocol):
    """Boundary between the AI gateway and a concrete model provider.

    The configured remote model can later be replaced by a local model without
    changing the domain layer. Providers only receive redacted input and only
    return validated structured drafts.
    """

    provider_id: str
    model_id: str

    async def generate_plan(self, summary: AiInputSummary) -> AiRecommendationDraft: ...


class AiProviderUnavailableError(RuntimeError):
    """Raised when no usable model provider is configured."""


class UnconfiguredAiProvider:
    """Placeholder used until a remote or local model is configured.

    It never produces recommendations; callers surface this as an explicit
    unavailable state instead of silently returning a fallback.
    """

    provider_id = "unconfigured"
    model_id = "none"

    async def generate_plan(self, summary: AiInputSummary) -> AiRecommendationDraft:
        raise AiProviderUnavailableError("No AI provider is configured.")
