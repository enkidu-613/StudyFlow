from __future__ import annotations

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from server.app.auth.password_policy import normalize_email, validate_password


class StrictRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    @field_validator("*", mode="before")
    @classmethod
    def reject_nul_strings(cls, value: object) -> object:
        if isinstance(value, str) and "\x00" in value:
            raise ValueError("NUL bytes are not allowed")
        return value


class RegisterRequest(StrictRequest):
    email: str = Field(min_length=1, max_length=320)
    password: str

    @field_validator("email")
    @classmethod
    def validate_email(cls, value: str) -> str:
        return normalize_email(value)

    @field_validator("password")
    @classmethod
    def validate_password_field(cls, value: str) -> str:
        return validate_password(value)


class LoginRequest(StrictRequest):
    email: str = Field(min_length=1, max_length=320)
    password: str = Field(min_length=1, max_length=256)

    @field_validator("email")
    @classmethod
    def validate_email(cls, value: str) -> str:
        return normalize_email(value)


class RefreshRequest(StrictRequest):
    refresh_token: str = Field(min_length=32, max_length=512)


class LogoutRequest(StrictRequest):
    refresh_token: str = Field(min_length=32, max_length=512)


class AuthResponse(BaseModel):
    user_id: UUID
    email: str
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int


class SessionResponse(BaseModel):
    user_id: UUID
    email: str


__all__ = [
    "AuthResponse",
    "LoginRequest",
    "LogoutRequest",
    "RefreshRequest",
    "RegisterRequest",
    "SessionResponse",
]
