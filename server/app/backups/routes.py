from __future__ import annotations

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from server.app.auth.dependencies import get_user_context
from server.app.backups.schemas import (
    BackupListResponse,
    BackupSummary,
    CreateBackupRequest,
    RenameBackupRequest,
)
from server.app.backups.service import BackupService, BackupServiceError
from server.app.db.context import UserContext


router = APIRouter(prefix="/v1/backups", tags=["backups"])


def get_backup_service(request: Request) -> BackupService:
    service = getattr(request.app.state, "backup_service", None)
    if service is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Backups are not configured.",
        )
    return service


@router.post("", response_model=BackupSummary, status_code=status.HTTP_201_CREATED)
async def create_backup(
    request: CreateBackupRequest,
    context: Annotated[UserContext, Depends(get_user_context)],
    service: Annotated[BackupService, Depends(get_backup_service)],
) -> BackupSummary:
    try:
        record = await service.create(context, name=request.name)
    except BackupServiceError as exc:
        raise _http_error(exc) from exc
    return BackupSummary.model_validate(record, from_attributes=True)


@router.get("", response_model=BackupListResponse)
async def list_backups(
    context: Annotated[UserContext, Depends(get_user_context)],
    service: Annotated[BackupService, Depends(get_backup_service)],
) -> BackupListResponse:
    records = await service.list(context)
    return BackupListResponse(
        backups=[
            BackupSummary.model_validate(record, from_attributes=True)
            for record in records
        ],
    )


@router.patch("/{backup_id}", response_model=BackupSummary)
async def rename_backup(
    backup_id: UUID,
    request: RenameBackupRequest,
    context: Annotated[UserContext, Depends(get_user_context)],
    service: Annotated[BackupService, Depends(get_backup_service)],
) -> BackupSummary:
    try:
        record = await service.rename(context, backup_id, request.name)
    except BackupServiceError as exc:
        raise _http_error(exc) from exc
    return BackupSummary.model_validate(record, from_attributes=True)


@router.delete("/{backup_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_backup(
    backup_id: UUID,
    context: Annotated[UserContext, Depends(get_user_context)],
    service: Annotated[BackupService, Depends(get_backup_service)],
) -> Response:
    try:
        await service.delete(context, backup_id)
    except BackupServiceError as exc:
        raise _http_error(exc) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def _http_error(exc: BackupServiceError) -> HTTPException:
    headers = {"WWW-Authenticate": "Bearer"} if exc.status_code == 401 else None
    return HTTPException(
        status_code=exc.status_code,
        detail=exc.detail,
        headers=headers or None,
    )
