part of 'app_database.dart';

class _Tasks extends Table {
  TextColumn get accountId => text()();
  TextColumn get recordId => text()();
  IntColumn get schemaVersion => integer()();
  BlobColumn get payloadNonce => blob()();
  BlobColumn get payloadCiphertext => blob()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, recordId};
}

class _ScheduleBlocks extends Table {
  TextColumn get accountId => text()();
  TextColumn get recordId => text()();
  IntColumn get schemaVersion => integer()();
  BlobColumn get payloadNonce => blob()();
  BlobColumn get payloadCiphertext => blob()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, recordId};
}

class _FocusSessions extends Table {
  TextColumn get accountId => text()();
  TextColumn get recordId => text()();
  IntColumn get schemaVersion => integer()();
  BlobColumn get payloadNonce => blob()();
  BlobColumn get payloadCiphertext => blob()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, recordId};
}

class _CheckIns extends Table {
  TextColumn get accountId => text()();
  TextColumn get recordId => text()();
  IntColumn get schemaVersion => integer()();
  BlobColumn get payloadNonce => blob()();
  BlobColumn get payloadCiphertext => blob()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, recordId};
}

class _PendingOperations extends Table {
  TextColumn get accountId => text()();
  TextColumn get operationId => text()();
  TextColumn get recordId => text()();
  TextColumn get deviceId => text()();
  IntColumn get logicalClock => integer()();
  TextColumn get entityType => text()();
  BlobColumn get payloadNonce => blob()();
  BlobColumn get payloadCiphertext => blob()();
  BoolColumn get isTombstone => boolean()();
  IntColumn get schemaVersion => integer()();
  DateTimeColumn get enqueuedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey =>
      <Column<Object>>{accountId, operationId};
}
