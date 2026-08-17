import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/features/alarm/pending_alarm.dart';
import 'package:studyflow/platform/platform_bridge.dart';
import 'package:studyflow_platform_contract/platform_contract.dart';

final class _FakeAlarmChannel implements PlatformMethodChannel {
  _FakeAlarmChannel(this.responses);

  final Map<String, Object?> responses;
  final List<String> methods = <String>[];

  @override
  Future<Object?> invokeMethod(String method, [Object? arguments]) async {
    methods.add(method);
    return responses[method];
  }
}

void main() {
  test('pending alarm parses its routing metadata', () {
    final alarm = PendingAlarm.fromJson(<String, Object?>{
      'id': 'focus:task-1',
      'title': '专注结束',
      'text': '请确认本次专注',
      'kind': 'focus',
      'entity_id': 'task-1',
    });

    expect(alarm.id, 'focus:task-1');
    expect(alarm.title, '专注结束');
    expect(alarm.kind, PendingAlarmKind.focus);
    expect(alarm.entityId, 'task-1');
  });

  test('schedule completion alarm exposes its occurrence start', () {
    final occurrenceStart = DateTime.utc(2026, 8, 17, 10, 30);
    final alarm = PendingAlarm.fromJson(<String, Object?>{
      'id': 'schedule:block-1:end:${occurrenceStart.millisecondsSinceEpoch}',
      'title': '学习结束',
      'text': '请确认这段日程是否完成',
      'kind': 'schedule',
      'entity_id': 'block-1',
    });

    expect(alarm.isScheduleCompletion, isTrue);
    expect(alarm.scheduleOccurrenceStart, occurrenceStart);
  });

  test('start schedule alarms are not completion alarms', () {
    final alarm = PendingAlarm.fromJson(<String, Object?>{
      'id': 'schedule:block-1#0',
      'kind': 'schedule',
      'entity_id': 'block-1',
    });

    expect(alarm.isScheduleCompletion, isFalse);
    expect(alarm.scheduleOccurrenceStart, isNull);
  });

  test('bridge reads persisted pending alarms', () async {
    final channel = _FakeAlarmChannel(<String, Object?>{
      'getPendingAlarms': <Object?>[
        <String, Object?>{
          'id': 'schedule:block-1#0',
          'title': '学习',
          'text': '开始学习',
          'kind': 'schedule',
          'entity_id': 'block-1',
        },
      ],
    });
    final bridge = PlatformBridge(channel: channel);

    final alarms = await bridge.getPendingAlarms();

    expect(alarms, hasLength(1));
    expect(alarms.single.kind, PendingAlarmKind.schedule);
    expect(channel.methods, <String>['getPendingAlarms']);
  });

  test('bridge exposes live alarm events and acknowledges an alarm', () async {
    final events = StreamController<PendingAlarm>();
    addTearDown(events.close);
    final channel = _FakeAlarmChannel(<String, Object?>{
      'acknowledgeAlarm': <String, Object?>{
        'kind': 'supported',
        'message': 'Alarm acknowledged.',
      },
    });
    final bridge = PlatformBridge(
      channel: channel,
      alarmEvents: events.stream,
    );
    final received = <PendingAlarm>[];
    final subscription = bridge.alarmEvents.listen(received.add);
    addTearDown(subscription.cancel);

    events.add(
      const PendingAlarm(
        id: 'schedule:block-1#0',
        title: '学习',
        text: '开始学习',
        kind: PendingAlarmKind.schedule,
        entityId: 'block-1',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final result = await bridge.acknowledgeAlarm('schedule:block-1#0');

    expect(received, hasLength(1));
    expect(result.kind, CapabilityResultKind.supported);
    expect(channel.methods, <String>['acknowledgeAlarm']);
  });
}
