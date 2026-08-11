from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, status

from server.app.ai.models import AiRecommendationRequest, AiRecommendationResponse
from server.app.ai.service import AiPolicyError, AiService
from server.app.auth.dependencies import get_account_context
from server.app.db.context import AccountContext


router = APIRouter(prefix="/v1/ai", tags=["ai"])


def get_ai_service(request: Request) -> AiService:
    service = getattr(request.app.state, "ai_service", None)
    if service is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI recommendations are not configured.",
        )
    return service


@router.post("/recommendations", response_model=AiRecommendationResponse)
async def create_recommendation(
    request: AiRecommendationRequest,
    context: Annotated[AccountContext, Depends(get_account_context)],
    service: Annotated[AiService, Depends(get_ai_service)],
) -> AiRecommendationResponse:
    try:
        recommendation = await service.generate_recommendation(
            account_id=context.account_id,
            summary=request.summary,
        )
    except AiPolicyError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
    return AiRecommendationResponse(recommendation=recommendation)
