from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from server.app.auth.password_blacklist import (
    COMMON_PASSWORDS,
    MemoryBreachedPasswordChecker,
    check_password_not_common,
)
from server.app.auth.rate_limit import LoginRateLimiter


class _Clock:
    def __init__(self, start: datetime) -> None:
        self.current = start

    def __call__(self) -> datetime:
        return self.current

    def advance(self, delta: timedelta) -> None:
        self.current += delta


def test_check_allows_until_attempt_limit_reached() -> None:
    clock = _Clock(datetime(2026, 8, 12, 3, 0, tzinfo=UTC))
    limiter = LoginRateLimiter(attempt_limit=3, clock=clock)

    for _ in range(3):
        assert limiter.check("ip|email").allowed is True
        limiter.record_failure("ip|email")

    blocked = limiter.check("ip|email")

    assert blocked.allowed is False
    assert blocked.retry_after_seconds > 0


def test_check_recovers_after_window_elapses() -> None:
    clock = _Clock(datetime(2026, 8, 12, 3, 0, tzinfo=UTC))
    limiter = LoginRateLimiter(
        attempt_limit=2,
        window=timedelta(minutes=10),
        clock=clock,
    )
    limiter.record_failure("ip|email")
    limiter.record_failure("ip|email")

    assert limiter.check("ip|email").allowed is False

    clock.advance(timedelta(minutes=11))

    assert limiter.check("ip|email").allowed is True


def test_successful_login_resets_failure_count() -> None:
    limiter = LoginRateLimiter(attempt_limit=3, clock=lambda: datetime.now(UTC))
    limiter.record_failure("ip|email")
    limiter.record_failure("ip|email")

    limiter.record_success("ip|email")

    assert limiter.check("ip|email").allowed is True


def test_failures_are_scoped_per_key() -> None:
    limiter = LoginRateLimiter(attempt_limit=1, clock=lambda: datetime.now(UTC))
    limiter.record_failure("ip1|a@example.com")

    assert limiter.check("ip1|a@example.com").allowed is False
    assert limiter.check("ip2|a@example.com").allowed is True
    assert limiter.check("ip1|b@example.com").allowed is True


def test_check_common_password_is_rejected() -> None:
    assert "Password1" in COMMON_PASSWORDS

    with pytest.raises(ValueError, match="公开泄露名单"):
        check_password_not_common("Password1")


def test_check_password_with_case_variation_is_rejected() -> None:
    with pytest.raises(ValueError, match="公开泄露名单"):
        check_password_not_common("PASSWORD1")


def test_check_uncommon_password_passes() -> None:
    assert check_password_not_common("Purple-Zebra-9") == "Purple-Zebra-9"


def test_memory_breached_checker_matches_case_insensitively() -> None:
    checker = MemoryBreachedPasswordChecker({"Correct-Horse-1"})

    assert checker._breached == {"correct-horse-1"}


@pytest.mark.anyio
async def test_memory_breached_checker_reports_breach() -> None:
    checker = MemoryBreachedPasswordChecker({"Correct-Horse-1"})

    assert await checker.is_breached("correct-horse-1") is True
    assert await checker.is_breached("Different-Pass-9") is False
