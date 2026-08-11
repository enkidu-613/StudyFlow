from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from server.app.scheduler.models import (
    ValidateScheduleProposalRequest,
    ValidateScheduleProposalResponse,
)
from server.app.scheduler.rules import SchedulePolicy


router = APIRouter(prefix="/v1/schedule", tags=["schedule"])


def get_schedule_policy() -> SchedulePolicy:
    return SchedulePolicy()


@router.post(
    "/proposals/validate",
    response_model=ValidateScheduleProposalResponse,
)
async def validate_proposal(
    request: ValidateScheduleProposalRequest,
    policy: Annotated[SchedulePolicy, Depends(get_schedule_policy)],
) -> ValidateScheduleProposalResponse:
    proposal = policy.propose(
        request.profile,
        request.history,
        request.existing_blocks,
    )
    return ValidateScheduleProposalResponse(proposal=proposal)
