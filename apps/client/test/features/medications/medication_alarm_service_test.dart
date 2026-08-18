import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/medications/medication_alarm_service.dart';
import 'package:studyflow/platform/platform_bridge.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow_domain/domain.dart';

final class _FakeMedicationPlatformChannel implements PlatformMethodChannel {
  final List<Map<String, Object?>> scheduled = <Map<String, Object?>>[];
  final List<Map<String, Object?>> cancelled = <Map<String, Object?>>[];

  @override
  Future<Object?> invokeMethod(String method, [Object? arguments]) async {
    final values =
        (arguments as Map<Object?, Object?>?)?.cast<String, Object?>() ??
            <String, Object?>{};
    if (method == 'scheduleReminder') {
      scheduled.add(values);
      return <String, Object?>{'kind': 'supported', 'message': 'ok'};
    }
    if (method == 'cancelReminder') {
      cancelled.add(values);
      return <String, Object?>{'kind': 'supported', 'message': 'ok'};
    }
    throw UnimplementedError(method);
  }
}

void main() {
  late Directory directory;
  late StudyFlowWorkspace workspace;
  late _FakeMedicationPlatformChannel channel;
  late MedicationAlarmService alarms;

  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('studyflow-medication-alarms-');
    channel = _FakeMedicationPlatformChannel();
    workspace = await StudyFlowWorkspace.openForTesting(
      accountId: '88888888-8888-4888-8888-888888888888',
      baseDirectory: directory,
      platform: PlatformBridge(channel: channel),
    );
    alarms = MedicationAlarmService(workspace: workspace);
  });

  tearDown(() async {
    alarms.dispose();
    await workspace.close();
    await directory.delete(recursive: true);
  });

  MedicationPlan plan({String id = '99999999-9999-4999-8999-999999999999'}) =>
      MedicationPlan(
        id: id,
        name: '测试药',
        strength: '10 mg',
        dose: '1 片',
        frequency: MedicationFrequency.daily,
        reminderTimes: const <MedicationTime>[
          MedicationTime(hour: 8, minute: 0),
          MedicationTime(hour: 20, minute: 0),
        ],
        startDate: DateTime.now(),
        enabled: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  test('schedules each daily medication reminder with medication metadata',
      () async {
    final medication = plan();
    await alarms.upsert(medication);

    expect(channel.scheduled, isNotEmpty);
    expect(channel.scheduled.every((call) => call['kind'] == 'medication'),
        isTrue);
    expect(
        channel.scheduled.every((call) => call['entity_id'] == medication.id),
        isTrue);
    expect(channel.scheduled.map((call) => call['id']),
        contains(contains(medication.id)));
  });

  test('does not schedule an occurrence already confirmed as taken',
      () async {
    final medication = plan();
    final occurrences = medication.occurrencesBetween(
      DateTime.now(),
      DateTime.now().add(const Duration(days: 30)),
    )..sort();
    final next = occurrences.firstWhere(
        (occurrence) => occurrence.isAfter(DateTime.now().add(
              const Duration(minutes: 1),
            )));
    await workspace.medications.saveDoseRecord(
      MedicationDoseRecord(
        id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        medicationPlanId: medication.id,
        plannedAt: next,
        outcome: MedicationDoseOutcome.taken,
        recordedAt: DateTime.now(),
      ),
      write: await workspace.nextWrite(),
    );

    await alarms.upsert(medication);

    final scheduledTimes = channel.scheduled
        .where((call) => (call['id'] as String).startsWith(medication.id))
        .map((call) => call['at'] as int)
        .toList(growable: false);
    // 已确认服用的那次不再注册：到点不响铃、不震动、不弹窗。
    expect(
        scheduledTimes,
        isNot(contains(next.toUtc().millisecondsSinceEpoch)));
    // 其余未来时间点照常注册。
    expect(scheduledTimes, isNotEmpty);
  });

  test('still schedules an occurrence recorded as skipped', () async {
    final medication = plan();
    final occurrences = medication.occurrencesBetween(
      DateTime.now(),
      DateTime.now().add(const Duration(days: 30)),
    )..sort();
    final next = occurrences.firstWhere(
        (occurrence) => occurrence.isAfter(DateTime.now().add(
              const Duration(minutes: 1),
            )));

    await workspace.medications.saveDoseRecord(
      MedicationDoseRecord(
        id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        medicationPlanId: medication.id,
        plannedAt: next,
        outcome: MedicationDoseOutcome.skipped,
        recordedAt: DateTime.now(),
      ),
      write: await workspace.nextWrite(),
    );

    await alarms.upsert(medication);

    final scheduledTimes = channel.scheduled
        .where((call) => (call['id'] as String).startsWith(medication.id))
        .map((call) => call['at'] as int)
        .toList(growable: false);
    // 只有“已服”才静音；跳过的时间点仍按原计划提醒。
    expect(scheduledTimes, contains(next.toUtc().millisecondsSinceEpoch));
  });

  test('cancels all future reminders for a medication plan', () async {
    final medication = plan();
    await alarms.upsert(medication);
    await alarms.cancel(medication.id);

    expect(channel.cancelled, isNotEmpty);
    expect(
        channel.cancelled
            .every((call) => (call['id'] as String).startsWith(medication.id)),
        isTrue);
  });

  test('startup resync tolerates corrupt records and still arms good plans',
      () async {
    final good = plan();
    await workspace.store.transaction((transaction) async {
      await transaction.putRecord(
        LocalRecord(
          accountId: workspace.accountId,
          recordId: good.id,
          entityType: EntityType.medicationPlan,
          schemaVersion: 1,
          payload: jsonEncode(good.toJson()),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      await transaction.putRecord(
        LocalRecord(
          accountId: workspace.accountId,
          recordId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          entityType: EntityType.medicationPlan,
          schemaVersion: 1,
          // 旧格式：缺少 reminderTimes，解析必然失败。
          payload: jsonEncode(<String, Object?>{'id': 'legacy', 'name': '旧数据'}),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    });

    final startupAlarms = MedicationAlarmService(workspace: workspace);
    try {
      // 构造函数里的 resync 是后台异步执行的；轮询直到排程完成。
      for (var attempt = 0;
          attempt < 100 && channel.scheduled.isEmpty;
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(channel.scheduled, isNotEmpty);
      expect(
        channel.scheduled
            .every((call) => (call['id'] as String).startsWith(good.id)),
        isTrue,
      );
    } finally {
      startupAlarms.dispose();
    }
  });
}
