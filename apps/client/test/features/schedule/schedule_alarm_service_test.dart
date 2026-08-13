import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/schedule/schedule_alarm_service.dart';
import 'package:studyflow/platform/platform_bridge.dart';
import 'package:studyflow_domain/domain.dart';

final class _FakePlatformMethodChannel implements PlatformMethodChannel {
  final List<Map<String, Object?>> alarmCalls = <Map<String, Object?>>[];

  @override
  Future<Object?> invokeMethod(String method, [Object? arguments]) async {
    if (method == 'playAlarm') {
      alarmCalls.add(
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
    alarms.upsert(block(start), title: 'Rest', text: 'Starts at 09:00');

    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(channel.alarmCalls, hasLength(1));
    expect(channel.alarmCalls.single['title'], 'Rest');
    expect(channel.alarmCalls.single['text'], 'Starts at 09:00');
  });

  test('alarm is cancelled after block deletion', () async {
    final start = DateTime.now().add(const Duration(seconds: 5));
    await workspace.schedule
        .save(block(start), write: await workspace.nextWrite());
    alarms.upsert(block(start), title: 'Rest', text: 'Later');
    alarms.cancel('bbbbbbbb-bbbb-4bbb-8bbb-000000000001');

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(channel.alarmCalls, isEmpty);
  });
}
