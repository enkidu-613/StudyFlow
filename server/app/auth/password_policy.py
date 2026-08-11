from __future__ import annotations

import re

EMAIL_MAX_LENGTH = 320
PASSWORD_MIN_LENGTH = 12
PASSWORD_MAX_LENGTH = 256


def normalize_email(value: str) -> str:
    if not isinstance(value, str):
        raise ValueError("email must be a string")
    normalized = value.strip().casefold()
    if not normalized:
        raise ValueError("email must not be empty")
    if len(normalized) > EMAIL_MAX_LENGTH:
        raise ValueError(f"email must be at most {EMAIL_MAX_LENGTH} characters")
    if "\x00" in normalized:
        raise ValueError("NUL bytes are not allowed")
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", normalized):
        raise ValueError("email must look like an email address")
    return normalized


def validate_password(value: str) -> str:
    if not isinstance(value, str):
        raise ValueError("password must be a string")
    if not (PASSWORD_MIN_LENGTH <= len(value) <= PASSWORD_MAX_LENGTH):
        raise ValueError(
            f"password must be between {PASSWORD_MIN_LENGTH} and "
            f"{PASSWORD_MAX_LENGTH} characters",
        )
    if "\x00" in value:
        raise ValueError("NUL bytes are not allowed")
    return value
