import 'dart:convert';

import 'package:studyflow/features/tasks/task_repository.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow_domain/domain.dart';

final class ScheduleRepository {
  ScheduleRepository({required AccountScopedStore store}) : _store = store;

  static const int _schemaVersion = 1;

  final AccountScopedStore _store;

  Future<void> save(
    ScheduleBlock block, {
    required Write write,
    DateTime? updatedAt,
  }) async {
    final payload = block.toJson();
    final record = LocalRecord(
      accountId: _store.activeAccountId,
      recordId: block.id,
      entityType: EntityType.scheduleBlock,
      schemaVersion: _schemaVersion,
      payload: jsonEncode(payload),
      updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
    );
    final operation = Operation(
      accountId: _store.activeAccountId,
      operationId: write.operationId,
      recordId: block.id,
      logicalClock: write.logicalClock,
      entityType: EntityType.scheduleBlock.wireName,
      payload: payload,
      isTombstone: false,
      schemaVersion: _schemaVersion,
    );

    await _store.transaction((transaction) async {
      await transaction.putRecord(record);
      await transaction.enqueue(operation);
    });
  }

  Future<ScheduleBlock?> get(String blockId) async {
    final record = await _store.records(EntityType.scheduleBlock).get(
          accountId: _store.activeAccountId,
          recordId: blockId,
        );
    if (record == null) {
      return null;
    }
    return _read(record);
  }

  Future<List<ScheduleBlock>> list() async {
    final records = await _store
        .records(EntityType.scheduleBlock)
        .list(accountId: _store.activeAccountId);
    final blocks = <ScheduleBlock>[];
    for (final record in records) {
      blocks.add(_read(record));
    }
    blocks.sort((left, right) => left.start.compareTo(right.start));
    return blocks;
  }

  ScheduleBlock _read(LocalRecord record) {
    final block = ScheduleBlock.fromJson(
      (jsonDecode(record.payload) as Map<String, dynamic>)
          .cast<String, Object?>(),
    );
    if (block.id != record.recordId) {
      throw const FormatException(
        'Schedule record id does not match payload id.',
      );
    }
    return block;
  }
}
