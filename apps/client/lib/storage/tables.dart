part of 'app_database.dart';

class _Tasks extends Table {
  TextColumn get accountId => text()();
  TextColumn get recordId => text()();
  IntColumn get schemaVersion => integer()();
  TextColumn get payload => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, recordId};
}

class _ScheduleBlocks extends Table {
  TextColumn get accountId => text()();
  TextColumn get recordId => text()();
  IntColumn get schemaVersion => integer()();
  TextColumn get payload => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, recordId};
}

class _FocusSessions extends Table {
  TextColumn get accountId => text()();
  TextColumn get recordId => text()();
  IntColumn get schemaVersion => integer()();
  TextColumn get payload => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, recordId};
}

class _CheckIns extends Table {
  TextColumn get accountId => text()();
  TextColumn get recordId => text()();
  IntColumn get schemaVersion => integer()();
  TextColumn get payload => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, recordId};
}

class _PendingOperations extends Table {
  TextColumn get accountId => text()();
  TextColumn get operationId => text()();
  TextColumn get recordId => text()();
  IntColumn get logicalClock => integer()();
  TextColumn get entityType => text()();
  TextColumn get payload => text()();
  IntColumn get isTombstone => integer()();
  IntColumn get schemaVersion => integer()();
  DateTimeColumn get queuedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, operationId};
}
