from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from server.app.scheduler.models import (
    CheckInSummary,
    ScheduleBlock,
    ScheduleProposal,
    SleepProfile,
)

WAKE_TIME_RE = re.compile(
    r"^(?P<hour>[01]\d|2[0-3]):(?P<minute>[0-5]\d)"
    r"(?P<offset>[+-](?:[01]\d|2[0-3]):[0-5]\d)?$"
)

# General behavioral boundary, not a diagnosis: adults are usually advised to
# get at least 7 hours of sleep regularly (CDC/AASM).
MIN_HEALTHY_SLEEP_MINUTES = 7 * 60
SEVERE_DEPRIVATION_MINUTES = 6 * 60
SEVERE_DEPRIVATION_HISTORY_SIZE = 2


class SchedulePolicyError(ValueError):
    """Raised for malformed policy inputs that cannot produce a proposal."""


class SchedulePolicy:
    """Deterministic sleep-window and schedule adjustment rules.

    The policy only proposes changes; it never persists anything. Proposals
    require explicit user confirmation (L2) before any schedule mutation.
    """

    def propose(
        self,
        profile: SleepProfile,
        history: list[CheckInSummary],
        existing_blocks: list[ScheduleBlock],
    ) -> ScheduleProposal:
        created_at = datetime.now(timezone.utc)
        reason_codes: list[str] = []

        if self._requires_professional_help(history):
            reason_codes.append("professional_help_recommended")
            return ScheduleProposal(
                proposal_id=uuid4(),
                original_blocks=existing_blocks,
                candidate_blocks=existing_blocks,
                reason_codes=reason_codes,
                requires_confirmation=False,
                sleep_start_delta_minutes=0,
                created_at=created_at,
            )

        reason_codes.append("sleep_adjustment_proposed")

        target_wake = _parse_target_wake(profile.target_wake_time)
        target_sleep_start = target_wake - timedelta(
            minutes=profile.target_sleep_duration_minutes
        )

        sleep_blocks = [
            block
            for block in existing_blocks
            if block.kind == "sleep" and not block.is_locked
        ]
        if not sleep_blocks:
            reason_codes.append("no_sleep_block_to_adjust")
            delta_minutes = 0
            candidate_blocks = existing_blocks
        else:
            block = sleep_blocks[0]
            raw_delta = _delta_minutes(block.start, target_sleep_start)
            requested_delta = _clamp(
                raw_delta,
                -profile.adjustment_step_minutes,
                profile.adjustment_step_minutes,
            )
            delta_minutes, candidate_blocks = _apply_adjustment(
                block=block,
                requested_delta=requested_delta,
                existing_blocks=existing_blocks,
                minimum_rest_minutes=profile.minimum_rest_minutes,
                reason_codes=reason_codes,
            )
            if delta_minutes == 0 and requested_delta != 0:
                reason_codes.append("adjustment_blocked_by_locked_or_rest")

        return ScheduleProposal(
            proposal_id=uuid4(),
            original_blocks=existing_blocks,
            candidate_blocks=candidate_blocks,
            reason_codes=reason_codes,
            requires_confirmation=True,
            sleep_start_delta_minutes=delta_minutes,
            created_at=created_at,
        )

    @staticmethod
    def _requires_professional_help(history: list[CheckInSummary]) -> bool:
        """Repeated severe deprivation or abnormal daytime tiredness.

        The policy never diagnoses; it only stops automatic adjustment and
        returns a professional-help reason code.
        """
        if len(history) < SEVERE_DEPRIVATION_HISTORY_SIZE:
            return False
        recent = history[-SEVERE_DEPRIVATION_HISTORY_SIZE:]
        avg_sleep = sum(item.sleep_minutes for item in recent) / len(recent)
        avg_energy = sum(item.energy for item in recent) / len(recent)
        return avg_sleep < SEVERE_DEPRIVATION_MINUTES and avg_energy <= 2


def _parse_target_wake(value: str) -> datetime:
    """Parse ``HH:MM+HH:MM`` into an aware UTC datetime anchored today.

    The wall-clock date is derived from the current UTC time shifted by the
    provided offset so the target wake time always lands on the same local day.
    """
    match = WAKE_TIME_RE.match(value)
    if match is None:
        raise SchedulePolicyError(
            "target_wake_time must look like 07:30+08:00"
        )
    hour = int(match.group("hour"))
    minute = int(match.group("minute"))
    offset_text = match.group("offset")
    if offset_text is None:
        raise SchedulePolicyError(
            "target_wake_time must carry an offset such as 07:30+08:00"
        )
    offset_sign = 1 if offset_text.startswith("+") else -1
    offset_hour, offset_minute = (int(part) for part in offset_text[1:].split(":"))
    local_offset = timezone(
        offset_sign * timedelta(hours=offset_hour, minutes=offset_minute)
    )
    local_wake = datetime.now(timezone.utc).astimezone(local_offset).replace(
        hour=hour, minute=minute, second=0, microsecond=0
    )
    return local_wake.astimezone(timezone.utc)


def _delta_minutes(start: datetime, target: datetime) -> int:
    return int((target - start).total_seconds() // 60)


def _clamp(value: int, low: int, high: int) -> int:
    return max(low, min(high, value))


def _delta_sequence(requested_delta: int) -> list[int]:
    """All deltas from the requested value down/up to zero, inclusive of zero."""
    if requested_delta >= 0:
        return list(range(requested_delta, -1, -1))
    return list(range(requested_delta, 1, 1))


def _apply_adjustment(
    *,
    block: ScheduleBlock,
    requested_delta: int,
    existing_blocks: list[ScheduleBlock],
    minimum_rest_minutes: int,
    reason_codes: list[str],
) -> tuple[int, list[ScheduleBlock]]:
    """Shift a sleep block by up to the requested delta without conflicts.

    Locked blocks are never moved. The delta shrinks towards zero until the
    shifted block no longer overlaps a locked block and keeps the configured
    minimum rest interval around its neighbours.
    """
    for delta in _delta_sequence(requested_delta):
        moved = _shift_block(block, delta)
        if _violates_locked(moved, existing_blocks) or _violates_rest(
            moved, existing_blocks, minimum_rest_minutes
        ):
            continue
        return delta, [moved if item.id == block.id else item for item in existing_blocks]

    reason_codes.append("sleep_block_not_shifted")
    return 0, existing_blocks


def _shift_block(block: ScheduleBlock, delta_minutes: int) -> ScheduleBlock:
    delta = timedelta(minutes=delta_minutes)
    return block.model_copy(
        update={
            "start": block.start + delta,
            "end": block.end + delta,
        }
    )


def _violates_locked(moved: ScheduleBlock, existing_blocks: list[ScheduleBlock]) -> bool:
    for other in existing_blocks:
        if other.id == moved.id or not other.is_locked:
            continue
        if moved.start < other.end and other.start < moved.end:
            return True
    return False


def _violates_rest(
    moved: ScheduleBlock,
    existing_blocks: list[ScheduleBlock],
    minimum_rest_minutes: int,
) -> bool:
    if minimum_rest_minutes <= 0:
        return False
    for other in existing_blocks:
        if other.id == moved.id:
            continue
        gap_minutes = _gap_minutes(moved, other)
        if gap_minutes is not None and gap_minutes < minimum_rest_minutes:
            return True
    return False


def _gap_minutes(left: ScheduleBlock, right: ScheduleBlock) -> int | None:
    """Return the gap between two blocks in minutes, or None if they overlap."""
    if left.start < right.start:
        if right.start < left.end:
            return None
        return int((right.start - left.end).total_seconds() // 60)
    if left.start > right.start:
        if left.start < right.end:
            return None
        return int((left.start - right.end).total_seconds() // 60)
    return None
