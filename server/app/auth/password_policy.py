from __future__ import annotations

import re
import string

EMAIL_MAX_LENGTH = 320
PASSWORD_MIN_LENGTH = 8
PASSWORD_MAX_LENGTH = 16

_PASSWORD_UPPERCASE = re.compile(r"[A-Z]")
_PASSWORD_LOWERCASE = re.compile(r"[a-z]")
_PASSWORD_DIGIT = re.compile(r"[0-9]")
_PASSWORD_SPECIAL = re.compile(r"[" + re.escape(string.punctuation) + r"]")

_PASSWORD_CATEGORY_LABELS = {
    "uppercase": "an uppercase letter",
    "lowercase": "a lowercase letter",
    "digit": "a digit",
    "special": "a special character",
}


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


def validate_password(value: str, *, email: str | None = None) -> str:
    if not isinstance(value, str):
        raise ValueError("password must be a string")
    if not (PASSWORD_MIN_LENGTH <= len(value) <= PASSWORD_MAX_LENGTH):
        raise ValueError(
            f"password must be between {PASSWORD_MIN_LENGTH} and "
            f"{PASSWORD_MAX_LENGTH} characters",
        )
    if "\x00" in value:
        raise ValueError("NUL bytes are not allowed")
    if " " in value:
        raise ValueError("password must not contain spaces")
    if value.isdigit():
        raise ValueError("password must not be all digits")
    if email is not None:
        normalized_email = email.strip().casefold()
        local_part = normalized_email.split("@", 1)[0]
        if value.casefold() in {normalized_email, local_part}:
            raise ValueError("password must not match the account email")
    missing_categories = _missing_password_categories(value)
    if missing_categories:
        missing_text = ", ".join(
            _PASSWORD_CATEGORY_LABELS[category] for category in missing_categories
        )
        raise ValueError(f"password must contain {missing_text}")
    return value


def _missing_password_categories(value: str) -> list[str]:
    checks = {
        "uppercase": _PASSWORD_UPPERCASE,
        "lowercase": _PASSWORD_LOWERCASE,
        "digit": _PASSWORD_DIGIT,
        "special": _PASSWORD_SPECIAL,
    }
    return [
        category
        for category, pattern in checks.items()
        if pattern.search(value) is None
    ]
