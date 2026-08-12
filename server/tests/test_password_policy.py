from __future__ import annotations

import pytest

from server.app.auth.password_policy import (
    PASSWORD_MAX_LENGTH,
    PASSWORD_MIN_LENGTH,
    validate_password,
)


VALID_PASSWORD = "Correct-Horse-1"


def test_valid_password_passes() -> None:
    assert validate_password(VALID_PASSWORD) == VALID_PASSWORD


def test_password_minimum_length_eight_is_accepted() -> None:
    password = "Ab1!cdef"
    assert len(password) == PASSWORD_MIN_LENGTH
    assert validate_password(password) == password


def test_password_maximum_length_sixteen_is_accepted() -> None:
    password = "Ab1!cdefghijklmn"
    assert len(password) == PASSWORD_MAX_LENGTH
    assert validate_password(password) == password


def test_password_shorter_than_eight_is_rejected() -> None:
    password = "Ab1!cde"
    assert len(password) == PASSWORD_MIN_LENGTH - 1
    with pytest.raises(ValueError, match="between 8 and"):
        validate_password(password)


def test_password_longer_than_sixteen_is_rejected() -> None:
    password = "A1!" + "a" * 20
    assert len(password) > PASSWORD_MAX_LENGTH
    with pytest.raises(ValueError, match="between 8 and"):
        validate_password(password)


@pytest.mark.parametrize(
    ("password", "missing_label"),
    [
        ("correct-horse-1", "an uppercase letter"),
        ("CORRECT-HORSE-1", "a lowercase letter"),
        ("Correct-Horse-B", "a digit"),
        ("CorrectHorse1", "a special character"),
    ],
)
def test_missing_single_category_is_rejected(
    password: str,
    missing_label: str,
) -> None:
    with pytest.raises(ValueError, match=missing_label):
        validate_password(password)


def test_password_with_all_categories_passes() -> None:
    assert validate_password("Correct-Horse-1") == "Correct-Horse-1"


def test_password_with_unicode_characters_and_all_ascii_categories_passes() -> None:
    assert validate_password("Caf\u00e9-Macaroon-1") == "Caf\u00e9-Macaroon-1"


def test_special_character_uses_ascii_punctuation() -> None:
    with pytest.raises(ValueError, match="a special character"):
        validate_password("CorrectHorse1\u4e2d\u6587")


def test_nul_byte_is_rejected() -> None:
    with pytest.raises(ValueError, match="NUL bytes"):
        validate_password("Correct\0-Horse-1")


def test_password_containing_spaces_is_rejected() -> None:
    with pytest.raises(ValueError, match="must not contain spaces"):
        validate_password("Correct Horse 1!")


def test_all_digit_password_is_rejected() -> None:
    with pytest.raises(ValueError, match="must not be all digits"):
        validate_password("12345678")


def test_password_matching_full_email_is_rejected() -> None:
    with pytest.raises(ValueError, match="must not match the account email"):
        validate_password("User@Example.Com", email="user@example.com")


def test_password_matching_email_local_part_is_rejected() -> None:
    with pytest.raises(ValueError, match="must not match the account email"):
        validate_password("username-1!", email="username-1!@example.com")


def test_password_different_from_email_passes() -> None:
    assert validate_password(
        "Correct-Horse-1",
        email="user@example.com",
    ) == "Correct-Horse-1"
