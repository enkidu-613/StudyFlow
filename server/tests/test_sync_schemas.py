from __future__ import annotations

import json
from pathlib import Path
from uuid import UUID

import pytest
from pydantic import ValidationError

from server.app.sync.schemas import SyncOperationV1


CONTRACT_FIXTURES = Path(__file__).resolve().parents[2] / "tests" / "contract"


def _load_fixture(name: str) -> dict[str, object]:
    return json.loads((CONTRACT_FIXTURES / name).read_text())


def test_push_fixture_round_trips_without_decrypting_payload() -> None:
    fixture = _load_fixture("sync_push_v1.json")
    operation = SyncOperationV1.model_validate(fixture["operations"][0])

    assert operation.schema_version == 1
    assert operation.payload_ciphertext
    assert operation.entity_type in {
        "task",
        "schedule_block",
        "focus_session",
        "check_in",
    }
    assert operation.operation_id == UUID("11111111-1111-4111-8111-111111111111")


def test_pull_fixture_serializes_to_the_same_wire_shape() -> None:
    fixture = _load_fixture("sync_pull_v1.json")
    operation = SyncOperationV1.model_validate(fixture["operations"][0])

    assert operation.model_dump(mode="json", by_alias=True) == fixture["operations"][0]


def test_uppercase_uuid_input_serializes_to_lowercase_wire_values() -> None:
    operation = dict(_load_fixture("sync_push_v1.json")["operations"][0])
    operation.update(
        {
            "operationId": "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF",
            "recordId": "FEDCBAFE-DCBA-4FED-8ABC-FEDCBAFEDCBA",
            "deviceId": "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEA",
        },
    )

    serialized = SyncOperationV1.model_validate(operation).model_dump(
        mode="json",
        by_alias=True,
    )

    assert serialized["operationId"] == "abcdefab-cdef-4abc-8def-abcdefabcdef"
    assert serialized["recordId"] == "fedcbafe-dcba-4fed-8abc-fedcbafedcba"
    assert serialized["deviceId"] == "abcdefab-cdef-4abc-8def-abcdefabcdea"


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("schemaVersion", 2),
        ("operationId", ""),
        ("operationId", "not-a-uuid"),
        ("recordId", "not-a-uuid"),
        ("deviceId", "not-a-uuid"),
        ("logicalClock", -1),
        ("entityType", "note"),
        ("payloadCiphertext", "not-base64!!!"),
    ],
)
def test_operation_rejects_invalid_wire_values(field: str, value: object) -> None:
    operation = dict(_load_fixture("sync_push_v1.json")["operations"][0])
    operation[field] = value

    with pytest.raises(ValidationError):
        SyncOperationV1.model_validate(operation)


def test_operation_rejects_ciphertext_larger_than_256_kibibytes() -> None:
    operation = dict(_load_fixture("sync_push_v1.json")["operations"][0])
    operation["payloadCiphertext"] = "A" * 349528

    with pytest.raises(ValidationError, match="256 KiB"):
        SyncOperationV1.model_validate(operation)


def test_operation_rejects_unknown_fields() -> None:
    operation = dict(_load_fixture("sync_push_v1.json")["operations"][0])
    operation["plaintext"] = "task title"

    with pytest.raises(ValidationError):
        SyncOperationV1.model_validate(operation)
