from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID


@dataclass(frozen=True, slots=True)
class AccountContext:
    account_id: UUID
    device_id: UUID
