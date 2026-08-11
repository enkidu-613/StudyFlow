from __future__ import annotations

from typing import Annotated
from uuid import UUID

from fastapi import Depends, Header, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from server.app.auth.service import AuthIdentity, AuthService, AuthServiceError
from server.app.db.context import AccountContext


bearer = HTTPBearer(auto_error=False)


def get_auth_service(request: Request) -> AuthService:
    service = getattr(request.app.state, "auth_service", None)
    if service is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication is not configured.",
        )
    return service


async def get_auth_identity(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    service: Annotated[AuthService, Depends(get_auth_service)],
) -> AuthIdentity:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Bearer access token is required.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        return await service.authenticate_access_token(credentials.credentials)
    except AuthServiceError as exc:
        headers = {"WWW-Authenticate": "Bearer"} if exc.status_code == 401 else None
        raise HTTPException(
            status_code=exc.status_code,
            detail=exc.detail,
            headers=headers,
        ) from exc


async def get_account_context(
    identity: Annotated[AuthIdentity, Depends(get_auth_identity)],
    device_id: Annotated[UUID, Header(alias="X-Device-Id")],
) -> AccountContext:
    if device_id != identity.device_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Device identity is not authorized.",
        )
    return AccountContext(
        account_id=identity.account_id,
        device_id=identity.device_id,
    )
