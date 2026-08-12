from __future__ import annotations

import hashlib
import json
import urllib.error
import urllib.request
from collections.abc import Awaitable, Callable

COMMON_PASSWORDS = frozenset(
    {
        "123456",
        "password",
        "12345678",
        "qwerty",
        "123456789",
        "12345",
        "1234",
        "111111",
        "1234567",
        "dragon",
        "123123",
        "baseball",
        "abc123",
        "football",
        "monkey",
        "letmein",
        "shadow",
        "master",
        "666666",
        "qwertyuiop",
        "123321",
        "mustang",
        "1234567890",
        "michael",
        "654321",
        "pussy",
        "superman",
        "1qaz2wsx",
        "7777777",
        "fuckyou",
        "121212",
        "000000",
        "qazwsx",
        "123qwe",
        "killer",
        "trustno1",
        "jordan",
        "jennifer",
        "zxcvbnm",
        "asdfgh",
        "hunter",
        "buster",
        "soccer",
        "harley",
        "batman",
        "andrew",
        "tigger",
        "sunshine",
        "iloveyou",
        "fuckme",
        "password1",
        "password123",
        "password!",
        "password1!",
        "Password1",
        "Password1!",
        "Qwerty123",
        "Qwerty123!",
        "qwerty123!",
        "admin123",
        "admin",
        "123456789a",
        "qwerty123",
        "passw0rd",
    },
)

HIBP_API_URL = "https://api.pwnedpasswords.com/range/"

_COMMON_PASSWORDS_CASEFOLDED = frozenset(
    password.casefold() for password in COMMON_PASSWORDS
)


def check_password_not_common(value: str) -> str:
    if value.casefold() in _COMMON_PASSWORDS_CASEFOLDED:
        raise ValueError("密码过于常见，已在公开泄露名单中")
    return value


class BreachedPasswordChecker:
    """Checks a password against publicly known breach corpuses.

    The default implementation queries the HIBP k-anonymity endpoint: only the
    first five characters of the password's SHA-1 digest are sent over the
    network, so the full password never leaves the client.
    """

    async def is_breached(self, password: str) -> bool:
        raise NotImplementedError

    async def close(self) -> None:
        return None


class HibpBreachedPasswordChecker(BreachedPasswordChecker):
    def __init__(
        self,
        *,
        timeout_seconds: float = 3.0,
        fetch: Callable[[str], Awaitable[bytes]] | None = None,
        api_url: str = HIBP_API_URL,
    ) -> None:
        self._timeout_seconds = timeout_seconds
        self._fetch = fetch or self._default_fetch
        self._api_url = api_url

    async def is_breached(self, password: str) -> bool:
        sha1 = hashlib.sha1(password.encode("utf-8")).hexdigest().upper()
        prefix, suffix = sha1[:5], sha1[5:]
        try:
            body = await self._fetch(f"{self._api_url}{prefix}")
        except (OSError, urllib.error.URLError, ValueError):
            # Fail open: a transient network problem must never block
            # registration; the built-in common-password list still applies.
            return False
        try:
            suffixes = {
                line.split(":", 1)[0]
                for line in body.decode("ascii", errors="ignore").splitlines()
            }
        except ValueError:
            return False
        return suffix in suffixes

    async def _default_fetch(self, url: str) -> bytes:
        def fetch() -> bytes:
            with urllib.request.urlopen(url, timeout=self._timeout_seconds) as response:
                return response.read()

        import asyncio

        return await asyncio.to_thread(fetch)


class MemoryBreachedPasswordChecker(BreachedPasswordChecker):
    """Deterministic checker for tests; no network access."""

    def __init__(self, breached: set[str] | None = None) -> None:
        self._breached = {value.casefold() for value in (breached or set())}

    async def is_breached(self, password: str) -> bool:
        return password.casefold() in self._breached


class NoopBreachedPasswordChecker(BreachedPasswordChecker):
    async def is_breached(self, password: str) -> bool:
        return False
