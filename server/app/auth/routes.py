from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from server.app.auth.dependencies import get_auth_service, get_user_context
from server.app.auth.models import (
    AuthResponse,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
    SessionResponse,
)
from server.app.auth.service import AuthService, AuthServiceError
from server.app.db.context import UserContext


router = APIRouter()


@router.post(
    "/v1/auth/register",
    response_model=AuthResponse,
    status_code=status.HTTP_201_CREATED,
)
async def register(
    request: RegisterRequest,
    service: Annotated[AuthService, Depends(get_auth_service)],
) -> AuthResponse:
    try:
        created = await service.register(request)
    except AuthServiceError as exc:
        raise _http_error(exc) from exc
    return AuthResponse.model_validate(created, from_attributes=True)


@router.post("/v1/auth/login", response_model=AuthResponse)
async def login(
    request: LoginRequest,
    http_request: Request,
    service: Annotated[AuthService, Depends(get_auth_service)],
) -> AuthResponse:
    source = (
        http_request.client.host
        if http_request.client is not None
        else "unknown"
    )
    try:
        authenticated = await service.login(
            email=request.email,
            password=request.password,
            source=source,
        )
    except AuthServiceError as exc:
        raise _http_error(exc) from exc
    return AuthResponse.model_validate(authenticated, from_attributes=True)


@router.post("/v1/auth/refresh", response_model=AuthResponse)
async def refresh(
    request: RefreshRequest,
    service: Annotated[AuthService, Depends(get_auth_service)],
) -> AuthResponse:
    try:
        authenticated = await service.refresh(request.refresh_token)
    except AuthServiceError as exc:
        raise _http_error(exc) from exc
    return AuthResponse.model_validate(authenticated, from_attributes=True)


@router.post("/v1/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    request: LogoutRequest,
    service: Annotated[AuthService, Depends(get_auth_service)],
) -> Response:
    try:
        await service.logout(request.refresh_token)
    except AuthServiceError as exc:
        raise _http_error(exc) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/v1/auth/session", response_model=SessionResponse)
async def session(
    context: Annotated[UserContext, Depends(get_user_context)],
) -> SessionResponse:
    return SessionResponse(user_id=context.user_id, email=context.email)


def _http_error(exc: AuthServiceError) -> HTTPException:
    headers: dict[str, str] = {}
    if exc.status_code == 401:
        headers["WWW-Authenticate"] = "Bearer"
    if exc.retry_after_seconds is not None:
        headers["Retry-After"] = str(exc.retry_after_seconds)
    return HTTPException(
        status_code=exc.status_code,
        detail=exc.detail,
        headers=headers or None,
    )
