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


def test_password_shorter_than_eight_is_rejected() -> None:
    password = "Ab1!cde"
    assert len(password) == PASSWORD_MIN_LENGTH - 1
    with pytest.raises(ValueError, match="between 8 and"):
        validate_password(password)


def test_password_longer_than_maximum_is_rejected() -> None:
    password = "A1!" + "a" * PASSWORD_MAX_LENGTH
    with pytest.raises(ValueError, match="between 8 and"):
        validate_password(password)


@pytest.mark.parametrize(
    ("password", "missing_label"),
    [
        ("correct-horse-1", "an uppercase letter"),
        ("CORRECT-HORSE-1", "a lowercase letter"),
        ("Correct-Horse-Battery", "a digit"),
        ("CorrectHorse1", "a special character"),
    ],
)
def test_missing_single_category_is_rejected(
    password: str,
    missing_label: str,
) -> None:
    with pytest.raises(ValueError, match=missing_label):
        validate_password(password)


def test_password_with_all_categories_and_spaces_passes() -> None:
    assert validate_password("Correct Horse 1 !") == "Correct Horse 1 !"


def test_password_with_unicode_characters_and_all_ascii_categories_passes() -> None:
    assert validate_password("Café-Macaroon-1") == "Café-Macaroon-1"


def test_special_character_uses_ascii_punctuation() -> None:
    with pytest.raises(ValueError, match="a special character"):
        validate_password("CorrectHorse1中文")


def test_nul_byte_is_rejected() -> None:
    with pytest.raises(ValueError, match="NUL bytes"):
        validate_password("Correct\0-Horse-1")


def test_unicode_and_space_do_not_count_as_special() -> None:
    with pytest.raises(ValueError, match="a special character"):
        validate_password("CorrectHorse1 ")
