import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/features/medications/medication_repository.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow/features/tasks/task_repository.dart';
import 'package:studyflow_domain/domain.dart';

void main() {
  late Directory directory;
  late AccountScopedStore store;
  late MedicationRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studyflow-medication-');
    store = await AccountScopedStore.openForTesting(
      activeAccountId: '11111111-1111-4111-8111-111111111111',
      baseDirectory: directory,
    );
    repository = MedicationRepository(store: store);
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  MedicationPlan plan() => MedicationPlan(
        id: '22222222-2222-4222-8222-222222222222',
        name: '测试药',
        strength: '10 mg',
        dose: '1 片',
        frequency: MedicationFrequency.daily,
        reminderTimes: const <MedicationTime>[
          MedicationTime(hour: 8, minute: 30)
        ],
        startDate: DateTime.utc(2026, 8, 17),
        enabled: true,
        createdAt: DateTime.utc(2026, 8, 17),
        updatedAt: DateTime.utc(2026, 8, 17),
      );

  test('save plan queues account-scoped medication sync operation', () async {
    await repository.savePlan(
      plan(),
      write: Write(
          operationId: '33333333-3333-4333-8333-333333333333', logicalClock: 1),
    );

    expect((await repository.listPlans()).single.name, '测试药');
    final operation = (await store.operations.pending(10)).single;
    expect(operation.entityType, 'medication_plan');
    expect(operation.payload.containsKey('rawMedicalOrder'), isFalse);
  });

  test('dose records use a separate sync entity', () async {
    final record = MedicationDoseRecord(
      id: '44444444-4444-4444-8444-444444444444',
      medicationPlanId: plan().id,
      plannedAt: DateTime.utc(2026, 8, 17, 8, 30),
      outcome: MedicationDoseOutcome.taken,
      recordedAt: DateTime.utc(2026, 8, 17, 8, 35),
    );
    await repository.saveDoseRecord(
      record,
      write: Write(
          operationId: '55555555-5555-4555-8555-555555555555', logicalClock: 2),
    );

    expect((await repository.listDoseRecords()).single.outcome,
        MedicationDoseOutcome.taken);
    expect((await store.operations.pending(10)).single.entityType,
        'medication_dose_record');
  });

  test('delete plan removes the local record and queues a tombstone', () async {
    final medication = plan();
    await repository.savePlan(
      medication,
      write: Write(
        operationId: '66666666-6666-4666-8666-666666666666',
        logicalClock: 3,
      ),
    );

    await repository.deletePlan(
      medication.id,
      write: Write(
        operationId: '77777777-7777-4777-8777-777777777777',
        logicalClock: 4,
      ),
    );

    expect(await repository.listPlans(), isEmpty);
    final operation = (await store.operations.pending(10)).last;
    expect(operation.entityType, 'medication_plan');
    expect(operation.isTombstone, isTrue);
    expect(operation.recordId, medication.id);
  });

  test('listPlans skips corrupt or legacy records instead of failing', () async {
    await repository.savePlan(
      plan(),
      write: Write(
        operationId: '88888888-8888-4888-8888-888888888888',
        logicalClock: 5,
      ),
    );
    await store.transaction((transaction) async {
      await transaction.putRecord(
        LocalRecord(
          accountId: store.activeAccountId,
          recordId: '99999999-9999-4999-8999-999999999998',
          entityType: EntityType.medicationPlan,
          schemaVersion: 1,
          // 旧格式：缺少 reminderTimes 等必填字段。
          payload: jsonEncode(<String, Object?>{
            'id': '99999999-9999-4999-8999-999999999998',
            'name': '旧版计划',
          }),
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      );
    });

    final plans = await repository.listPlans();

    expect(plans.length, 1);
    expect(plans.single.name, '测试药');
  });

  test('listDoseRecords skips corrupt records instead of failing', () async {
    await store.transaction((transaction) async {
      await transaction.putRecord(
        LocalRecord(
          accountId: store.activeAccountId,
          recordId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          entityType: EntityType.medicationDoseRecord,
          schemaVersion: 1,
          payload: jsonEncode(<String, Object?>{'id': 'broken'}),
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      );
    });

    expect(await repository.listDoseRecords(), isEmpty);
  });
}
