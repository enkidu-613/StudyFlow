from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status

from server.app.auth.dependencies import get_account_context
from server.app.db.context import AccountContext
from server.app.sync.schemas import (
    SyncPullResponse,
    SyncPushRequest,
    SyncPushResponse,
)
from server.app.sync.service import (
    SyncAccessDeniedError,
    SyncConflictError,
    SyncService,
)


router = APIRouter(prefix="/v1/sync", tags=["sync"])


def get_sync_service(request: Request) -> SyncService:
    service = getattr(request.app.state, "sync_service", None)
    if service is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Synchronization is not configured.",
        )
    return service


@router.post("/push", response_model=SyncPushResponse)
async def push(
    request: SyncPushRequest,
    context: Annotated[AccountContext, Depends(get_account_context)],
    service: Annotated[SyncService, Depends(get_sync_service)],
) -> SyncPushResponse:
    try:
        result = await service.push(context, request.operations)
    except SyncAccessDeniedError as exc:
        raise _access_denied() from exc
    except SyncConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Operation ID conflicts with stored ciphertext.",
        ) from exc
    return SyncPushResponse.model_validate(result, from_attributes=True)


@router.get("/pull", response_model=SyncPullResponse)
async def pull(
    context: Annotated[AccountContext, Depends(get_account_context)],
    service: Annotated[SyncService, Depends(get_sync_service)],
    after: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> SyncPullResponse:
    try:
        result = await service.pull(context, after=after, limit=limit)
    except SyncAccessDeniedError as exc:
        raise _access_denied() from exc
    return SyncPullResponse(
        next_cursor=result.next_cursor,
        operations=[item.operation for item in result.operations],
    )


def _access_denied() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Device identity is not authorized.",
    )
