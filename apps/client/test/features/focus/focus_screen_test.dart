import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/focus/focus_screen.dart';
import 'package:studyflow/platform/platform_bridge.dart';
import 'package:studyflow_domain/domain.dart';
import '../../helpers/l10n_test_app.dart';

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
    if (method == 'startFocusSession') {
      return <String, Object?>{'kind': 'supported', 'message': 'ok'};
    }
    throw UnimplementedError('unexpected method: $method');
  }
}

void main() {
  late Directory directory;
  late StudyFlowWorkspace workspace;
  late _FakePlatformMethodChannel channel;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studyflow-focus-test-');
    channel = _FakePlatformMethodChannel();
    workspace = await StudyFlowWorkspace.openForTesting(
      accountId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      baseDirectory: directory,
      platform: PlatformBridge(channel: channel),
    );
  });

  tearDown(() async {
    await workspace.close();
    await directory.delete(recursive: true);
  });

  Task task({int minutes = 1}) => Task(
        id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        title: 'One Minute',
        description: '',
        estimatedMinutes: minutes,
        priority: TaskPriority.normal,
        status: TaskStatus.todo,
        tags: <String>[],
        repeatRule: RepeatRule.none,
      );

  testWidgets('focus finishes automatically when the task duration elapses',
      (tester) async {
    await tester.runAsync(() async {
      await workspace.tasks.save(task(), write: await workspace.nextWrite());
    });

    var fakeNow = DateTime(2026, 1, 1, 9, 0, 0);
    await pumpWithL10n(
      tester,
      FocusScreen(
        workspace: workspace,
        now: () => fakeNow,
      ),
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start'));
    await tester.pump();
    fakeNow = fakeNow.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Time remaining'), findsNothing);
    expect(find.text('Start'), findsOneWidget);

    final sessions = await tester.runAsync(workspace.focus.list);
    expect(sessions, hasLength(1));
    expect(sessions!.single.completionMethod, FocusCompletionMethod.timer);
    expect(channel.alarmCalls, hasLength(1));
    expect(channel.alarmCalls.single['title'], 'One Minute focus complete');
  });

  testWidgets('focus shows countdown to the task duration', (tester) async {
    await tester.runAsync(() async {
      await workspace.tasks.save(task(), write: await workspace.nextWrite());
    });

    var fakeNow = DateTime(2026, 1, 1, 9, 0, 0);
    await pumpWithL10n(
      tester,
      FocusScreen(
        workspace: workspace,
        now: () => fakeNow,
      ),
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start'));
    await tester.pump();
    fakeNow = fakeNow.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Time remaining'), findsOneWidget);
    expect(find.text('00:00:59'), findsOneWidget);

    fakeNow = fakeNow.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Time remaining'), findsNothing);
  });
}
