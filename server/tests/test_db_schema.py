from uuid import uuid4

import pytest
from sqlalchemy import UniqueConstraint

from server.app.db.models import (
    Device,
    SyncOperation,
    User,
    UserSession,
    UserSyncOperation,
)
from server.app.db.context import AccountContext
from server.app.db.repositories import (
    DeviceOwnershipConflictError,
    SyncOperationPayload,
    SyncOperationRepository,
)


def test_user_table_has_unique_normalized_email() -> None:
    primary_key_columns = {column.name for column in User.__table__.primary_key.columns}
    unique_constraints = {
        tuple(column.name for column in constraint.columns)
        for constraint in User.__table__.constraints
        if isinstance(constraint, UniqueConstraint)
    }

    assert primary_key_columns == {"user_id"}
    assert ("email_normalized",) in unique_constraints
    assert {column.name for column in User.__table__.columns}.issuperset(
        {
            "user_id",
            "email",
            "email_normalized",
            "password_hash",
            "created_at",
            "updated_at",
        },
    )


def test_user_sessions_reference_user_and_unique_token_digest() -> None:
    unique_constraints = {
        tuple(column.name for column in constraint.columns)
        for constraint in UserSession.__table__.constraints
        if isinstance(constraint, UniqueConstraint)
    }
    foreign_keys = list(UserSession.__table__.foreign_key_constraints)

    assert ("token_digest",) in unique_constraints
    assert len(foreign_keys) == 1
    assert foreign_keys[0].referred_table is User.__table__


def test_user_sync_operations_scope_by_user_and_hold_json_payload() -> None:
    primary_key_columns = {
        column.name for column in UserSyncOperation.__table__.primary_key.columns
    }
    unique_constraints = {
        tuple(column.name for column in constraint.columns)
        for constraint in UserSyncOperation.__table__.constraints
        if isinstance(constraint, UniqueConstraint)
    }
    foreign_keys = list(UserSyncOperation.__table__.foreign_key_constraints)
    column_types = {
        column.name: str(column.type)
        for column in UserSyncOperation.__table__.columns
    }

    assert primary_key_columns == {"server_sequence"}
    assert ("user_id", "operation_id") in unique_constraints
    assert len(foreign_keys) == 1
    assert foreign_keys[0].referred_table is User.__table__
    assert "JSON" in column_types["payload"]


def test_device_table_scopes_ownership_by_account_and_keeps_device_id_globally_unique() -> None:
    primary_key_columns = {column.name for column in Device.__table__.primary_key.columns}
    unique_constraints = {
        tuple(column.name for column in constraint.columns)
        for constraint in Device.__table__.constraints
        if isinstance(constraint, UniqueConstraint)
    }

    assert primary_key_columns == {"account_id", "device_id"}
    assert ("device_id",) in unique_constraints


def test_sync_operations_reference_the_account_device_pair() -> None:
    device_foreign_keys = [
        constraint
        for constraint in SyncOperation.__table__.foreign_key_constraints
        if constraint.referred_table is Device.__table__
    ]

    assert len(device_foreign_keys) == 1
    assert {element.parent.name for element in device_foreign_keys[0].elements} == {
        "account_id",
        "device_id",
    }


@pytest.mark.anyio
@pytest.mark.integration
async def test_sync_metadata_has_opaque_payload_columns(database) -> None:
    columns = await database.columns("sync_operations")

    assert {"account_id", "operation_id", "record_id", "server_sequence"}.issubset(columns)
    assert {"payload_nonce", "payload_ciphertext", "is_tombstone"}.issubset(columns)


@pytest.mark.anyio
@pytest.mark.integration
async def test_readiness_reports_database_status(client) -> None:
    response = await client.get("/health/ready")

    assert response.status_code == 200
    assert response.json()["database"] == "ok"


@pytest.mark.anyio
@pytest.mark.integration
async def test_request_account_context_cannot_read_another_accounts_rows(database) -> None:
    repository = SyncOperationRepository(database.session_factory)

    first_context = AccountContext(account_id=uuid4(), device_id=uuid4())
    second_context = AccountContext(account_id=uuid4(), device_id=uuid4())
    first_result = await repository.insert_operation(
        first_context,
        SyncOperationPayload(
            operation_id=uuid4(),
            record_id=uuid4(),
            payload_nonce=b"nonce-1",
            payload_ciphertext=b"ciphertext-1",
        ),
    )
    second_result = await repository.insert_operation(
        second_context,
        SyncOperationPayload(
            operation_id=uuid4(),
            record_id=uuid4(),
            payload_nonce=b"nonce-2",
            payload_ciphertext=b"ciphertext-2",
        ),
    )

    first_visible = await database.visible_server_sequences(first_context.account_id)
    second_visible = await database.visible_server_sequences(second_context.account_id)

    assert first_result.inserted is True
    assert second_result.inserted is True
    assert first_result.server_sequence in first_visible
    assert second_result.server_sequence not in first_visible
    assert second_result.server_sequence in second_visible


@pytest.mark.anyio
@pytest.mark.integration
async def test_insert_operation_is_idempotent_per_account_and_operation(database) -> None:
    repository = SyncOperationRepository(database.session_factory)

    context = AccountContext(account_id=uuid4(), device_id=uuid4())
    operation_id = uuid4()
    first_insert = await repository.insert_operation(
        context,
        SyncOperationPayload(
            operation_id=operation_id,
            record_id=uuid4(),
            payload_nonce=b"nonce-repeat",
            payload_ciphertext=b"ciphertext-repeat",
        ),
    )
    second_insert = await repository.insert_operation(
        context,
        SyncOperationPayload(
            operation_id=operation_id,
            record_id=uuid4(),
            payload_nonce=b"nonce-repeat",
            payload_ciphertext=b"ciphertext-repeat",
        ),
    )

    assert first_insert.inserted is True
    assert first_insert.server_sequence is not None
    assert second_insert.inserted is False
    assert second_insert.server_sequence is None


@pytest.mark.anyio
@pytest.mark.integration
async def test_reusing_a_device_id_for_another_account_raises_an_explicit_conflict(database) -> None:
    repository = SyncOperationRepository(database.session_factory)
    shared_device_id = uuid4()

    first_context = AccountContext(account_id=uuid4(), device_id=shared_device_id)
    second_context = AccountContext(account_id=uuid4(), device_id=shared_device_id)

    await repository.insert_operation(
        first_context,
        SyncOperationPayload(
            operation_id=uuid4(),
            record_id=uuid4(),
            payload_nonce=b"nonce-owner-a",
            payload_ciphertext=b"ciphertext-owner-a",
        ),
    )

    with pytest.raises(DeviceOwnershipConflictError, match="already belongs to account"):
        await repository.insert_operation(
            second_context,
            SyncOperationPayload(
                operation_id=uuid4(),
                record_id=uuid4(),
                payload_nonce=b"nonce-owner-b",
                payload_ciphertext=b"ciphertext-owner-b",
            ),
        )


@pytest.mark.anyio
@pytest.mark.integration
async def test_new_tables_exist_after_migrations(database) -> None:
    users = await database.columns("users")
    sessions = await database.columns("user_sessions")
    sync_ops = await database.columns("user_sync_operations")

    assert {"user_id", "email", "email_normalized", "password_hash"}.issubset(users)
    assert {"session_id", "user_id", "token_digest", "revoked_at"}.issubset(sessions)
    assert {
        "user_id",
        "operation_id",
        "record_id",
        "server_sequence",
        "payload",
    }.issubset(sync_ops)


@pytest.mark.anyio
@pytest.mark.integration
async def test_new_tables_are_not_row_level_security_forced(database) -> None:
    for table_name in ("users", "user_sessions", "user_sync_operations"):
        row_security, force_security = await database.row_security(table_name)
        assert row_security is False
        assert force_security is False

