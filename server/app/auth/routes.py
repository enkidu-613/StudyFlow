from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Header, HTTPException, Request, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from server.app.auth.models import (
    AuthResponse,
    BootstrapRequest,
    CreatePairingCodeRequest,
    LoginRequest,
    PairDeviceRequest,
    PairingCodeResponse,
    RefreshRequest,
    RevokeDeviceRequest,
    SessionResponse,
)
from server.app.auth.service import AuthIdentity, AuthService, AuthServiceError


router = APIRouter()
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
        raise _http_error(exc) from exc


@router.post(
    "/v1/auth/bootstrap",
    response_model=AuthResponse,
    status_code=status.HTTP_201_CREATED,
)
async def bootstrap(
    request: BootstrapRequest,
    service: Annotated[AuthService, Depends(get_auth_service)],
    bootstrap_token: Annotated[str, Header(alias="X-StudyFlow-Bootstrap-Token")],
) -> AuthResponse:
    try:
        created = await service.bootstrap(
            presented_bootstrap_token=bootstrap_token,
            password=request.password.get_secret_value(),
            device_id=request.device_id,
            public_key=request.device_public_key,
            envelope=request.encrypted_account_data_key_envelope,
        )
    except AuthServiceError as exc:
        raise _http_error(exc) from exc
    return AuthResponse.model_validate(created, from_attributes=True)


@router.post("/v1/auth/login", response_model=AuthResponse)
async def login(
    request: LoginRequest,
    service: Annotated[AuthService, Depends(get_auth_service)],
) -> AuthResponse:
    try:
        authenticated = await service.login(
            password=request.password.get_secret_value(),
            device_id=request.device_id,
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
        authenticated = await service.refresh(request.refresh_token.get_secret_value())
    except AuthServiceError as exc:
        raise _http_error(exc) from exc
    return AuthResponse.model_validate(authenticated, from_attributes=True)


@router.get("/v1/auth/session", response_model=SessionResponse)
async def session(identity: Annotated[AuthIdentity, Depends(get_auth_identity)]) -> SessionResponse:
    return SessionResponse(account_id=identity.account_id, device_id=identity.device_id)


@router.post(
    "/v1/devices/pairing-codes",
    response_model=PairingCodeResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_pairing_code(
    request: CreatePairingCodeRequest,
    identity: Annotated[AuthIdentity, Depends(get_auth_identity)],
    service: Annotated[AuthService, Depends(get_auth_service)],
) -> PairingCodeResponse:
    try:
        created = await service.create_pairing_code(
            identity,
            target_device_id=request.target_device_id,
            target_device_public_key=request.target_device_public_key,
            envelope=request.encrypted_account_data_key_envelope,
        )
    except AuthServiceError as exc:
        raise _http_error(exc) from exc
    return PairingCodeResponse.model_validate(created, from_attributes=True)


@router.post("/v1/devices/pair", response_model=AuthResponse)
async def pair_device(
    request: PairDeviceRequest,
    service: Annotated[AuthService, Depends(get_auth_service)],
) -> AuthResponse:
    try:
        authenticated = await service.pair(
            code=request.code,
            device_id=request.device_id,
            device_public_key=request.device_public_key,
        )
    except AuthServiceError as exc:
        raise _http_error(exc) from exc
    return AuthResponse.model_validate(authenticated, from_attributes=True)


@router.post("/v1/devices/revoke", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_device(
    request: RevokeDeviceRequest,
    identity: Annotated[AuthIdentity, Depends(get_auth_identity)],
    service: Annotated[AuthService, Depends(get_auth_service)],
) -> Response:
    try:
        await service.revoke_device(identity, request.device_id)
    except AuthServiceError as exc:
        raise _http_error(exc) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def _http_error(exc: AuthServiceError) -> HTTPException:
    headers = {"WWW-Authenticate": "Bearer"} if exc.status_code == 401 else None
    return HTTPException(status_code=exc.status_code, detail=exc.detail, headers=headers)
