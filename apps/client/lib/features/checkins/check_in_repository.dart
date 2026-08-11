import 'dart:convert';

import 'package:studyflow/features/tasks/task_repository.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow_domain/domain.dart';

final class CheckInRepository {
  CheckInRepository({required AccountScopedStore store}) : _store = store;

  static const int _schemaVersion = 1;

  final AccountScopedStore _store;

  Future<void> save(
    CheckIn checkIn, {
    required Write write,
    DateTime? updatedAt,
  }) async {
    final payload = checkIn.toJson();
    final record = LocalRecord(
      accountId: _store.activeAccountId,
      recordId: checkIn.id,
      entityType: EntityType.checkIn,
      schemaVersion: _schemaVersion,
      payload: jsonEncode(payload),
      updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
    );
    final operation = Operation(
      accountId: _store.activeAccountId,
      operationId: write.operationId,
      recordId: checkIn.id,
      logicalClock: write.logicalClock,
      entityType: EntityType.checkIn.wireName,
      payload: payload,
      isTombstone: false,
      schemaVersion: _schemaVersion,
    );

    await _store.transaction((transaction) async {
      await transaction.putRecord(record);
      await transaction.enqueue(operation);
    });
  }

  Future<CheckIn?> get(String checkInId) async {
    final record = await _store.records(EntityType.checkIn).get(
          accountId: _store.activeAccountId,
          recordId: checkInId,
        );
    if (record == null) {
      return null;
    }
    return _read(record);
  }

  Future<List<CheckIn>> list() async {
    final records = await _store
        .records(EntityType.checkIn)
        .list(accountId: _store.activeAccountId);
    final checkIns = <CheckIn>[];
    for (final record in records) {
      checkIns.add(_read(record));
    }
    checkIns.sort((left, right) => right.recordedAt.compareTo(left.recordedAt));
    return checkIns;
  }

  CheckIn _read(LocalRecord record) {
    final checkIn = CheckIn.fromJson(
      (jsonDecode(record.payload) as Map<String, dynamic>)
          .cast<String, Object?>(),
    );
    if (checkIn.id != record.recordId) {
      throw const FormatException(
        'Check-in record id does not match payload id.',
      );
    }
    return checkIn;
  }
}
