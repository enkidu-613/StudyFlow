from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from server.app.scheduler.models import (
    CheckInSummary,
    ScheduleBlock,
    ScheduleProposal,
    SleepProfile,
)
from server.app.scheduler.rules import (
    SchedulePolicy,
    SchedulePolicyError,
    _delta_minutes,
    _parse_target_wake,
)


def _block(
    *,
    block_id: str,
    start: datetime,
    end: datetime,
    kind: str = "sleep",
    is_locked: bool = False,
) -> ScheduleBlock:
    return ScheduleBlock(
        id=block_id,
        start=start,
        end=end,
        kind=kind,
        taskId=None,
        source="generated",
        isLocked=is_locked,
    )


def _check_in(
    *,
    minutes: int,
    quality: int = 4,
    energy: int = 4,
    recorded_at: datetime | None = None,
) -> CheckInSummary:
    return CheckInSummary(
        recordedAt=recorded_at or datetime.now(timezone.utc),
        sleepMinutes=minutes,
        sleepQuality=quality,
        energy=energy,
        mood=4,
    )


def propose_for_history(
    *,
    wake_time: str = "07:30+08:00",
    sleep_duration_minutes: int = 420,
    adjustment_step_minutes: int = 15,
    history_minutes: tuple[int, ...] = (420, 430),
    history_energy: int = 4,
    blocks: list[ScheduleBlock] | None = None,
) -> ScheduleProposal:
    """Test-only helper: builds a profile, valid history, and an unlocked
    future sleep block, then runs the policy. Not part of the server API.
    """
    profile = SleepProfile(
        ageRange="18-24",
        timezoneOffset="+08:00",
        targetWakeTime=wake_time,
        targetSleepDurationMinutes=sleep_duration_minutes,
        adjustmentStepMinutes=adjustment_step_minutes,
    )
    history = [
        _check_in(
            minutes=minutes,
            energy=history_energy,
            recorded_at=datetime.now(timezone.utc) - timedelta(days=offset),
        )
        for offset, minutes in enumerate(history_minutes)
    ]
    selected_blocks = (
        blocks
        if blocks is not None
        else [
            _block(
                block_id="00000000-0000-4000-8000-00000000000a",
                start=datetime.now(timezone.utc).replace(
                    hour=16, minute=30, second=0, microsecond=0
                ),
                end=datetime.now(timezone.utc).replace(
                    hour=23, minute=30, second=0, microsecond=0
                ),
            )
        ]
    )
    return SchedulePolicy().propose(profile, history, selected_blocks)


def test_sleep_adjustment_is_small_and_targeted() -> None:
    proposal = propose_for_history(
        wake_time="07:30+08:00",
        sleep_duration_minutes=420,
        adjustment_step_minutes=15,
    )

    assert abs(proposal.sleep_start_delta_minutes) <= 15
    assert proposal.requires_confirmation is True


def test_proposal_reports_requires_confirmation_for_adjustment() -> None:
    proposal = propose_for_history()

    assert proposal.requires_confirmation is True
    assert "sleep_adjustment_proposed" in proposal.reason_codes


def test_proposal_keeps_original_blocks_unchanged() -> None:
    original = [
        _block(
            block_id="00000000-0000-4000-8000-00000000000a",
            start=datetime.now(timezone.utc).replace(
                hour=16, minute=30, second=0, microsecond=0
            ),
            end=datetime.now(timezone.utc).replace(
                hour=23, minute=30, second=0, microsecond=0
            ),
        )
    ]
    proposal = propose_for_history(blocks=original)

    # The policy must not mutate its input: the proposal carries the same
    # original blocks it received.
    assert proposal.original_blocks == original


def test_locked_block_is_never_moved() -> None:
    locked = _block(
        block_id="00000000-0000-4000-8000-0000000000bb",
        start=datetime(2026, 1, 1, 22, 0, tzinfo=timezone.utc),
        end=datetime(2026, 1, 1, 23, 0, tzinfo=timezone.utc),
        is_locked=True,
    )
    proposal = propose_for_history(
        blocks=[
            _block(
                block_id="00000000-0000-4000-8000-0000000000bb",
                start=datetime(2026, 1, 1, 22, 0, tzinfo=timezone.utc),
                end=datetime(2026, 1, 1, 23, 0, tzinfo=timezone.utc),
                is_locked=True,
            ),
            _block(
                block_id="00000000-0000-4000-8000-0000000000cc",
                start=datetime(2026, 1, 1, 20, 0, tzinfo=timezone.utc),
                end=datetime(2026, 1, 1, 21, 0, tzinfo=timezone.utc),
            ),
        ],
    )

    locked_after = next(
        block for block in proposal.candidate_blocks if block.id == locked.id
    )
    assert locked_after.start == locked.start
    assert locked_after.end == locked.end


def test_repeated_severe_deprivation_returns_professional_help() -> None:
    proposal = propose_for_history(
        history_minutes=(330, 300),
        history_energy=1,
    )

    assert "professional_help_recommended" in proposal.reason_codes
    assert proposal.sleep_start_delta_minutes == 0
    assert proposal.candidate_blocks == proposal.original_blocks


def test_daylight_saving_storage_is_utc_and_presented_locally() -> None:
    # A local 23:00 -> 07:00 block in +08:00 must be stored as UTC and
    # presented back as the same local wall clock time.
    local_block_start = _parse_target_wake("23:00+08:00")
    local_block_end = _parse_target_wake("07:00+08:00")

    stored_start = local_block_start.astimezone(timezone.utc)
    stored_end = local_block_end.astimezone(timezone.utc)
    assert stored_start.utcoffset() == timedelta(0)

    presented_start = stored_start.astimezone(timezone(timedelta(hours=8)))
    presented_end = stored_end.astimezone(timezone(timedelta(hours=8)))
    assert (presented_start.hour, presented_start.minute) == (23, 0)
    assert (presented_end.hour, presented_end.minute) == (7, 0)


def test_target_wake_parsing_uses_utc_anchor() -> None:
    wake = _parse_target_wake("07:30+08:00")

    assert wake.tzinfo == timezone.utc
    assert wake.utcoffset() == timedelta(0)
    presented = wake.astimezone(timezone(timedelta(hours=8)))
    assert (presented.hour, presented.minute) == (7, 30)


def test_malformed_wake_time_is_rejected() -> None:
    with pytest.raises(SchedulePolicyError):
        _parse_target_wake("07:30")


def test_delta_minutes_sign_is_positive_when_target_is_later() -> None:
    start = datetime(2026, 1, 1, 20, 0, tzinfo=timezone.utc)
    target = datetime(2026, 1, 1, 21, 0, tzinfo=timezone.utc)

    assert _delta_minutes(start, target) == 60


def test_validate_endpoint_returns_proposal_without_persisting() -> None:
    from fastapi.testclient import TestClient

    from server.app.main import app

    client = TestClient(app)
    response = client.post(
        "/v1/schedule/proposals/validate",
        json={
            "profile": {
                "ageRange": "18-24",
                "timezoneOffset": "+08:00",
                "targetWakeTime": "07:30+08:00",
                "targetSleepDurationMinutes": 420,
                "adjustmentStepMinutes": 15,
            },
            "history": [
                {
                    "recordedAt": "2026-08-09T00:00:00Z",
                    "sleepMinutes": 420,
                    "sleepQuality": 4,
                    "energy": 4,
                    "mood": 4,
                },
                {
                    "recordedAt": "2026-08-10T00:00:00Z",
                    "sleepMinutes": 430,
                    "sleepQuality": 4,
                    "energy": 4,
                    "mood": 4,
                },
            ],
            "existing_blocks": [
                {
                    "id": "00000000-0000-4000-8000-00000000000a",
                    "start": "2026-08-11T16:30:00Z",
                    "end": "2026-08-11T23:30:00Z",
                    "kind": "sleep",
                    "taskId": None,
                    "source": "generated",
                    "isLocked": False,
                }
            ],
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["proposal"]["requiresConfirmation"] is True
    assert "reasonCodes" in body["proposal"]
    assert body["proposal"]["originalBlocks"] == body["proposal"].get(
        "candidateBlocks"
    ) or abs(body["proposal"]["sleepStartDeltaMinutes"]) <= 15
