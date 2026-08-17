import 'dart:convert';

import 'package:studyflow/features/tasks/task_repository.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow_domain/domain.dart';

final class ScheduleFeedbackRepository {
  ScheduleFeedbackRepository({required AccountScopedStore store})
      : _store = store;

  static const int _schemaVersion = 1;

  final AccountScopedStore _store;

  Future<void> save(
    ScheduleFeedback feedback, {
    required Write write,
    DateTime? updatedAt,
  }) async {
    final payload = feedback.toJson();
    final record = LocalRecord(
      accountId: _store.activeAccountId,
      recordId: feedback.id,
      entityType: EntityType.scheduleFeedback,
      schemaVersion: _schemaVersion,
      payload: jsonEncode(payload),
      updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
    );
    final operation = Operation(
      accountId: _store.activeAccountId,
      operationId: write.operationId,
      recordId: feedback.id,
      logicalClock: write.logicalClock,
      entityType: EntityType.scheduleFeedback.wireName,
      payload: payload,
      isTombstone: false,
      schemaVersion: _schemaVersion,
    );
    await _store.transaction((transaction) async {
      await transaction.putRecord(record);
      await transaction.enqueue(operation);
    });
  }

  Future<ScheduleFeedback?> get(String feedbackId) async {
    final record = await _store.records(EntityType.scheduleFeedback).get(
          accountId: _store.activeAccountId,
          recordId: feedbackId,
        );
    return record == null ? null : _read(record);
  }

  Future<ScheduleFeedback?> findForOccurrence({
    required String scheduleBlockId,
    required DateTime occurrenceEnd,
  }) async {
    final expectedEnd = occurrenceEnd.toUtc();
    for (final feedback in await list()) {
      if (feedback.scheduleBlockId == scheduleBlockId &&
          feedback.occurrenceEnd.isAtSameMomentAs(expectedEnd)) {
        return feedback;
      }
    }
    return null;
  }

  Future<List<ScheduleFeedback>> list({int? limit}) async {
    if (limit != null && limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    final records = await _store.records(EntityType.scheduleFeedback).list(
          accountId: _store.activeAccountId,
        );
    final feedback = records.map(_read).toList()
      ..sort((left, right) => right.confirmedAt.compareTo(left.confirmedAt));
    return limit == null ? feedback : feedback.take(limit).toList();
  }

  ScheduleFeedback _read(LocalRecord record) {
    final feedback = ScheduleFeedback.fromJson(
      (jsonDecode(record.payload) as Map<String, dynamic>)
          .cast<String, Object?>(),
    );
    if (feedback.id != record.recordId) {
      throw const FormatException(
        'Schedule feedback record id does not match payload id.',
      );
    }
    return feedback;
  }
}
