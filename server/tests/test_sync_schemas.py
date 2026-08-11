from __future__ import annotations

import json
from pathlib import Path
from uuid import UUID

import pytest
from pydantic import ValidationError

from server.app.sync.schemas import SyncOperationV2


CONTRACT_FIXTURES = Path(__file__).resolve().parents[2] / "tests" / "contract"


def _load_fixture(name: str) -> dict[str, object]:
    return json.loads((CONTRACT_FIXTURES / name).read_text())


def test_push_fixture_round_trips_without_transforming_payload() -> None:
    fixture = _load_fixture("sync_push_v2.json")
    operation = SyncOperationV2.model_validate(fixture["operations"][0])

    assert operation.schema_version == 1
    assert operation.payload == {"title": "Read chapter 1", "status": "pending"}
    assert operation.entity_type in {
        "task",
        "schedule_block",
        "focus_session",
        "check_in",
    }
    assert operation.operation_id == UUID("11111111-1111-4111-8111-111111111111")


def test_pull_fixture_serializes_to_the_same_wire_shape() -> None:
    fixture = _load_fixture("sync_pull_v2.json")
    operation = SyncOperationV2.model_validate(fixture["operations"][0])

    assert operation.model_dump(mode="json", by_alias=True) == fixture["operations"][0]


def test_uppercase_uuid_input_serializes_to_lowercase_wire_values() -> None:
    operation = dict(_load_fixture("sync_push_v2.json")["operations"][0])
    operation.update(
        {
            "operationId": "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF",
            "recordId": "FEDCBAFE-DCBA-4FED-8ABC-FEDCBAFEDCBA",
        },
    )

    serialized = SyncOperationV2.model_validate(operation).model_dump(
        mode="json",
        by_alias=True,
    )

    assert serialized["operationId"] == "abcdefab-cdef-4abc-8def-abcdefabcdef"
    assert serialized["recordId"] == "fedcbafe-dcba-4fed-8abc-fedcbafedcba"


def test_payload_must_be_a_json_object() -> None:
    with pytest.raises(ValidationError):
        SyncOperationV2.model_validate(
            {
                "operationId": "11111111-1111-4111-8111-111111111111",
                "recordId": "22222222-2222-4222-8222-222222222222",
                "logicalClock": 0,
                "entityType": "task",
                "payload": "not-an-object",
                "isTombstone": False,
                "schemaVersion": 1,
            },
        )


def test_non_tombstone_payload_must_not_be_empty() -> None:
    with pytest.raises(ValidationError):
        SyncOperationV2.model_validate(
            {
                "operationId": "11111111-1111-4111-8111-111111111111",
                "recordId": "22222222-2222-4222-8222-222222222222",
                "logicalClock": 0,
                "entityType": "task",
                "payload": {},
                "isTombstone": False,
                "schemaVersion": 1,
            },
        )


def test_tombstone_operation_allows_empty_payload() -> None:
    operation = SyncOperationV2.model_validate(
        {
            "operationId": "11111111-1111-4111-8111-111111111111",
            "recordId": "22222222-2222-4222-8222-222222222222",
            "logicalClock": 0,
            "entityType": "task",
            "payload": {},
            "isTombstone": True,
            "schemaVersion": 1,
        },
    )

    assert operation.payload == {}


def test_unknown_schema_version_is_rejected() -> None:
    operation = dict(_load_fixture("sync_push_v2.json")["operations"][0])
    operation["schemaVersion"] = 2

    with pytest.raises(ValidationError):
        SyncOperationV2.model_validate(operation)


def test_unknown_entity_type_is_rejected() -> None:
    operation = dict(_load_fixture("sync_push_v2.json")["operations"][0])
    operation["entityType"] = "note"

    with pytest.raises(ValidationError):
        SyncOperationV2.model_validate(operation)


def test_extra_user_id_field_is_rejected() -> None:
    operation = dict(_load_fixture("sync_push_v2.json")["operations"][0])
    operation["userId"] = "11111111-1111-4111-8111-111111111111"

    with pytest.raises(ValidationError):
        SyncOperationV2.model_validate(operation)
