import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:studyflow/features/tasks/task_repository.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow_domain/domain.dart';

final class MedicationRepository {
  MedicationRepository({required AccountScopedStore store}) : _store = store;

  static const int _schemaVersion = 1;
  final AccountScopedStore _store;

  Future<void> savePlan(MedicationPlan plan, {required Write write}) => _save(
        id: plan.id,
        entityType: EntityType.medicationPlan,
        payload: plan.toJson(),
        write: write,
        updatedAt: plan.updatedAt,
      );

  Future<void> deletePlan(String planId, {required Write write}) async {
    final operation = Operation(
      accountId: _store.activeAccountId,
      operationId: write.operationId,
      recordId: planId,
      logicalClock: write.logicalClock,
      entityType: EntityType.medicationPlan.wireName,
      payload: const <String, Object?>{},
      isTombstone: true,
      schemaVersion: _schemaVersion,
    );
    await _store.transaction((transaction) async {
      await transaction.deleteRecord(EntityType.medicationPlan, planId);
      await transaction.enqueue(operation);
    });
  }

  Future<void> saveDoseRecord(MedicationDoseRecord record,
          {required Write write}) =>
      _save(
        id: record.id,
        entityType: EntityType.medicationDoseRecord,
        payload: record.toJson(),
        write: write,
        updatedAt: record.recordedAt,
      );

  Future<List<MedicationPlan>> listPlans() async {
    final records = await _store.records(EntityType.medicationPlan).list(
          accountId: _store.activeAccountId,
        );
    final plans = <MedicationPlan>[];
    for (final record in records) {
      try {
        plans.add(MedicationPlan.fromJson(_payload(record)));
      } on Object {
        // 旧版本或损坏的记录只跳过本身，不能让整张计划列表失败，
        // 否则启动排程和药物页面会被单条坏数据整体拖垮。
        debugPrint('StudyFlow: skipped unparsable medication plan record '
            '${record.recordId}');
      }
    }
    plans.sort((left, right) => left.name.compareTo(right.name));
    return plans;
  }

  Future<List<MedicationDoseRecord>> listDoseRecords() async {
    final records = await _store.records(EntityType.medicationDoseRecord).list(
          accountId: _store.activeAccountId,
        );
    final doses = <MedicationDoseRecord>[];
    for (final record in records) {
      try {
        doses.add(MedicationDoseRecord.fromJson(_payload(record)));
      } on Object {
        debugPrint('StudyFlow: skipped unparsable dose record '
            '${record.recordId}');
      }
    }
    doses.sort((left, right) => right.recordedAt.compareTo(left.recordedAt));
    return doses;
  }

  Future<void> _save({
    required String id,
    required EntityType entityType,
    required Map<String, Object?> payload,
    required Write write,
    required DateTime updatedAt,
  }) async {
    if (_containsRawMedicalOrder(payload)) {
      throw ArgumentError.value(
          payload, 'payload', 'must not contain raw medical orders');
    }
    final record = LocalRecord(
      accountId: _store.activeAccountId,
      recordId: id,
      entityType: entityType,
      schemaVersion: _schemaVersion,
      payload: jsonEncode(payload),
      updatedAt: updatedAt.toUtc(),
    );
    final operation = Operation(
      accountId: _store.activeAccountId,
      operationId: write.operationId,
      recordId: id,
      logicalClock: write.logicalClock,
      entityType: entityType.wireName,
      payload: payload,
      isTombstone: false,
      schemaVersion: _schemaVersion,
    );
    await _store.transaction((transaction) async {
      await transaction.putRecord(record);
      await transaction.enqueue(operation);
    });
  }

  Map<String, Object?> _payload(LocalRecord record) =>
      (jsonDecode(record.payload) as Map<String, dynamic>)
          .cast<String, Object?>();
}

bool _containsRawMedicalOrder(Object? value) {
  if (value is Map) {
    return value.entries.any(
      (entry) =>
          entry.key == 'rawMedicalOrder' ||
          _containsRawMedicalOrder(entry.value),
    );
  }
  if (value is Iterable) return value.any(_containsRawMedicalOrder);
  return false;
}
