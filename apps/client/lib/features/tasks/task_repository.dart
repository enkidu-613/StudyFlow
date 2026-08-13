import 'dart:convert';

import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow_domain/domain.dart';

final class Write {
  Write({
    required this.operationId,
    required this.logicalClock,
  }) {
    if (logicalClock < 0) {
      throw ArgumentError.value(
          logicalClock, 'logicalClock', 'must be non-negative');
    }
  }

  final String operationId;
  final int logicalClock;
}

final class TaskRepository {
  TaskRepository({required AccountScopedStore store}) : _store = store;

  static const int _schemaVersion = 1;

  final AccountScopedStore _store;

  Future<void> save(
    Task task, {
    required Write write,
    DateTime? updatedAt,
  }) async {
    final payload = task.toJson();
    final record = LocalRecord(
      accountId: _store.activeAccountId,
      recordId: task.id,
      entityType: EntityType.task,
      schemaVersion: _schemaVersion,
      payload: jsonEncode(payload),
      updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
    );
    final operation = Operation(
      accountId: _store.activeAccountId,
      operationId: write.operationId,
      recordId: task.id,
      logicalClock: write.logicalClock,
      entityType: EntityType.task.wireName,
      payload: payload,
      isTombstone: false,
      schemaVersion: _schemaVersion,
    );

    await _store.transaction((transaction) async {
      await transaction.putRecord(record);
      await transaction.enqueue(operation);
    });
  }

  Future<void> delete(String taskId, {required Write write}) async {
    final operation = Operation(
      accountId: _store.activeAccountId,
      operationId: write.operationId,
      recordId: taskId,
      logicalClock: write.logicalClock,
      entityType: EntityType.task.wireName,
      payload: const <String, Object?>{},
      isTombstone: true,
      schemaVersion: _schemaVersion,
    );

    await _store.transaction((transaction) async {
      await transaction.deleteRecord(EntityType.task, taskId);
      await transaction.enqueue(operation);
    });
  }

  Future<Task?> get(String taskId) async {
    final record = await _store.records(EntityType.task).get(
          accountId: _store.activeAccountId,
          recordId: taskId,
        );
    if (record == null) {
      return null;
    }
    return _read(record);
  }

  Future<List<Task>> list() async {
    final records = await _store
        .records(EntityType.task)
        .list(accountId: _store.activeAccountId);
    final tasks = <Task>[];
    for (final record in records) {
      tasks.add(_read(record));
    }
    tasks.sort((left, right) => left.title.compareTo(right.title));
    return tasks;
  }

  Task _read(LocalRecord record) {
    final task = Task.fromJson(
      (jsonDecode(record.payload) as Map<String, dynamic>)
          .cast<String, Object?>(),
    );
    if (task.id != record.recordId) {
      throw const FormatException('Task record id does not match payload id.');
    }
    return task;
  }
}
