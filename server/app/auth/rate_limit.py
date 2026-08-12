from __future__ import annotations

from collections import defaultdict, deque
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta


@dataclass(frozen=True, slots=True)
class RateLimitDecision:
    allowed: bool
    retry_after_seconds: int


class LoginRateLimiter:
    """In-memory sliding-window limiter keyed by ``source|email``.

    Failed logins are recorded per identity (client IP plus normalized email)
    so that one attacker cannot exhaust other accounts and one user cannot be
    locked out by another client's failures.
    """

    def __init__(
        self,
        *,
        attempt_limit: int = 5,
        window: timedelta = timedelta(minutes=10),
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        if attempt_limit < 1 or window <= timedelta(0):
            raise ValueError("Rate limiter settings must be positive.")
        self._attempt_limit = attempt_limit
        self._window = window
        self._clock = clock or (lambda: datetime.now(UTC))
        self._failures: dict[str, deque[datetime]] = defaultdict(deque)

    def check(self, key: str) -> RateLimitDecision:
        now = self._clock()
        cutoff = now - self._window
        failures = self._failures[key]
        while failures and failures[0] <= cutoff:
            failures.popleft()
        if len(failures) >= self._attempt_limit:
            oldest = failures[0]
            retry_after = (oldest + self._window - now).total_seconds()
            return RateLimitDecision(
                allowed=False,
                retry_after_seconds=max(1, int(retry_after) + 1),
            )
        return RateLimitDecision(allowed=True, retry_after_seconds=0)

    def record_failure(self, key: str) -> None:
        self._failures[key].append(self._clock())

    def record_success(self, key: str) -> None:
        self._failures.pop(key, None)

    def reset(self) -> None:
        self._failures.clear()
