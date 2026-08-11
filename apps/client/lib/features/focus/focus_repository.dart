import 'dart:convert';

import 'package:studyflow/features/tasks/task_repository.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow_domain/domain.dart';

final class FocusRepository {
  FocusRepository({required AccountScopedStore store}) : _store = store;

  static const int _schemaVersion = 1;

  final AccountScopedStore _store;

  Future<void> save(
    FocusSession session, {
    required Write write,
    DateTime? updatedAt,
  }) async {
    final payload = session.toJson();
    final record = LocalRecord(
      accountId: _store.activeAccountId,
      recordId: session.id,
      entityType: EntityType.focusSession,
      schemaVersion: _schemaVersion,
      payload: jsonEncode(payload),
      updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
    );
    final operation = Operation(
      accountId: _store.activeAccountId,
      operationId: write.operationId,
      recordId: session.id,
      logicalClock: write.logicalClock,
      entityType: EntityType.focusSession.wireName,
      payload: payload,
      isTombstone: false,
      schemaVersion: _schemaVersion,
    );

    await _store.transaction((transaction) async {
      await transaction.putRecord(record);
      await transaction.enqueue(operation);
    });
  }

  Future<FocusSession?> get(String sessionId) async {
    final record = await _store.records(EntityType.focusSession).get(
          accountId: _store.activeAccountId,
          recordId: sessionId,
        );
    if (record == null) {
      return null;
    }
    return _read(record);
  }

  Future<List<FocusSession>> list() async {
    final records = await _store
        .records(EntityType.focusSession)
        .list(accountId: _store.activeAccountId);
    final sessions = <FocusSession>[];
    for (final record in records) {
      sessions.add(_read(record));
    }
    sessions.sort((left, right) => right.startedAt.compareTo(left.startedAt));
    return sessions;
  }

  FocusSession _read(LocalRecord record) {
    final session = FocusSession.fromJson(
      (jsonDecode(record.payload) as Map<String, dynamic>)
          .cast<String, Object?>(),
    );
    if (session.id != record.recordId) {
      throw const FormatException(
        'Focus record id does not match payload id.',
      );
    }
    return session;
  }
}
