import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/schedule/schedule_alarm_service.dart';
import 'package:studyflow/platform/platform_bridge.dart';
import 'package:studyflow_domain/domain.dart';

final class _FakePlatformMethodChannel implements PlatformMethodChannel {
  bool scheduleSupported = true;
  Duration scheduleDelay = Duration.zero;
  final List<Map<String, Object?>> alarmCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> scheduledCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> cancelledCalls = <Map<String, Object?>>[];

  @override
  Future<Object?> invokeMethod(String method, [Object? arguments]) async {
    if (method == 'playAlarm') {
      alarmCalls.add(
        (arguments as Map<Object?, Object?>).cast<String, Object?>(),
      );
      return <String, Object?>{'kind': 'supported', 'message': 'ok'};
    }
    if (method == 'scheduleReminder') {
      if (scheduleDelay > Duration.zero) {
        await Future<void>.delayed(scheduleDelay);
      }
      scheduledCalls.add(
        (arguments as Map<Object?, Object?>).cast<String, Object?>(),
      );
      return <String, Object?>{
        'kind': scheduleSupported ? 'supported' : 'unsupported',
        'message': 'ok',
      };
    }
    if (method == 'cancelReminder') {
      cancelledCalls.add(
        (arguments as Map<Object?, Object?>).cast<String, Object?>(),
      );
      return <String, Object?>{'kind': 'supported', 'message': 'ok'};
    }
    throw UnimplementedError('unexpected method: $method');
  }
}

void main() {
  late Directory directory;
  late StudyFlowWorkspace workspace;
  late _FakePlatformMethodChannel channel;
  late ScheduleAlarmService alarms;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studyflow-alarms-');
    channel = _FakePlatformMethodChannel();
    workspace = await StudyFlowWorkspace.openForTesting(
      accountId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      baseDirectory: directory,
      platform: PlatformBridge(channel: channel),
    );
    alarms = ScheduleAlarmService(workspace: workspace);
  });

  tearDown(() async {
    alarms.dispose();
    await workspace.close();
    await directory.delete(recursive: true);
  });

  ScheduleBlock block(
    DateTime start, {
    String id = 'bbbbbbbb-bbbb-4bbb-8bbb-000000000001',
  }) =>
      ScheduleBlock(
        id: id,
        start: start,
        end: start.add(const Duration(hours: 1)),
        kind: ScheduleBlockKind.rest,
        taskId: null,
        source: ScheduleBlockSource.manual,
        isLocked: false,
      );

  test('alarm fires with title and text when a block starts', () async {
    final start = DateTime.now().add(const Duration(milliseconds: 200));
    await workspace.schedule
        .save(block(start), write: await workspace.nextWrite());
    await alarms.upsert(block(start), title: 'Rest', text: 'Starts at 09:00');

    expect(channel.scheduledCalls, hasLength(2));
    expect(
      channel.scheduledCalls.map((call) => call['id']),
      containsAll(<Object?>[
        contains('#0'),
        contains(':end:'),
      ]),
    );
    final endCall = channel.scheduledCalls.singleWhere(
      (call) => (call['id'] as String).contains(':end:'),
    );
    expect(
      endCall['at'],
      closeTo(
        start.add(const Duration(hours: 1)).toUtc().millisecondsSinceEpoch,
        1000,
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(channel.alarmCalls, isEmpty);
  });

  test('alarm is cancelled after block deletion', () async {
    final start = DateTime.now().add(const Duration(seconds: 5));
    await workspace.schedule
        .save(block(start), write: await workspace.nextWrite());
    await alarms.upsert(block(start), title: 'Rest', text: 'Later');
    await alarms.cancel('bbbbbbbb-bbbb-4bbb-8bbb-000000000001');

    expect(channel.cancelledCalls.length, greaterThanOrEqualTo(2));
    expect(
      channel.cancelledCalls.map((call) => call['id']),
      contains('bbbbbbbb-bbbb-4bbb-8bbb-000000000001'),
    );

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(channel.alarmCalls, isEmpty);
  });

  test('an active block still arms its future end alarm', () async {
    final now = DateTime.now();
    final current = ScheduleBlock(
      id: 'bbbbbbbb-bbbb-4bbb-8bbb-000000000002',
      start: now.subtract(const Duration(seconds: 1)),
      end: now.add(const Duration(seconds: 5)),
      kind: ScheduleBlockKind.rest,
      taskId: null,
      source: ScheduleBlockSource.manual,
      isLocked: false,
    );
    await workspace.schedule.save(current, write: await workspace.nextWrite());
    await alarms.upsert(current, title: 'Rest', text: 'In progress');

    expect(channel.scheduledCalls, hasLength(1));
    expect(channel.scheduledCalls.single['id'], contains(':end:'));
  });

  test('a slow successful native schedule does not trigger a fallback alarm',
      () async {
    channel.scheduleDelay = const Duration(milliseconds: 300);
    final start = DateTime.now().add(const Duration(milliseconds: 100));
    await workspace.schedule
        .save(block(start), write: await workspace.nextWrite());
    await alarms.upsert(block(start), title: 'Rest', text: 'Later');

    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(channel.scheduledCalls, hasLength(2));
    expect(channel.alarmCalls, isEmpty);
  });
}
