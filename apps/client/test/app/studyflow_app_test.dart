import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/tasks/task_editor_screen.dart';
import 'package:studyflow/main.dart';
import 'package:studyflow/security/key_manager.dart';
import 'package:studyflow_domain/domain.dart';

void main() {
  late Directory directory;
  late StudyFlowWorkspace workspace;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studyflow-app-test-');
    final keyManager = KeyManager(
      accountId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      store: MemorySecureKeyStore(),
    );
    workspace = await StudyFlowWorkspace.openForTesting(
      keyManager: keyManager,
      baseDirectory: directory,
    );
  });

  tearDown(() async {
    await workspace.close();
    await directory.delete(recursive: true);
  });

  testWidgets('shell exposes all StudyFlow routes', (tester) async {
    await tester.pumpWidget(StudyFlowApp(workspace: workspace));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in <String>[
      'Tasks',
      'Schedule',
      'Focus',
      'Settings',
    ]) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('task creation is saved to the encrypted local store',
      (tester) async {
    await tester.pumpWidget(StudyFlowApp(workspace: workspace));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('task-title-field')),
      'Read chapter 1',
    );
    await tester.enterText(
      find.byKey(const Key('task-minutes-field')),
      '30',
    );
    await tester.dragUntilVisible(
      find.byKey(const Key('save-task-button')),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('save-task-button')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Title is required.'), findsNothing);
    expect(find.text('Minutes must be positive.'), findsNothing);
    expect(find.byType(TaskEditorScreen), findsNothing);
    expect(await tester.runAsync(workspace.pendingCount), 1);
    final savedTasks = await tester.runAsync(workspace.tasks.list);
    expect(
      savedTasks!.single.title,
      'Read chapter 1',
    );
    expect(find.text('Read chapter 1'), findsOneWidget);
  });

  testWidgets('schedule block creation reaches the schedule list',
      (tester) async {
    await tester.pumpWidget(StudyFlowApp(workspace: workspace));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Save'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(await tester.runAsync(workspace.schedule.list), isNotEmpty);
    expect(await tester.runAsync(workspace.pendingCount), 1);
  });

  testWidgets('focus session starts and finishes into encrypted storage',
      (tester) async {
    await tester.runAsync(() async {
      await workspace.tasks.save(
        _task,
        write: await workspace.nextWrite(),
      );
    });
    await tester.pumpWidget(StudyFlowApp(workspace: workspace));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Finish'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    final sessions = await tester.runAsync(workspace.focus.list);
    expect(sessions, isNotEmpty);
    expect(await tester.runAsync(workspace.pendingCount), 2);
  });

  testWidgets('settings shows permission health and pending sync',
      (tester) async {
    await tester.pumpWidget(StudyFlowApp(workspace: workspace));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pending sync'), findsOneWidget);
    expect(find.text('Permissions'), findsOneWidget);
  });
}

final _task = Task(
  id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  title: 'Algebra',
  description: '',
  estimatedMinutes: 25,
  priority: TaskPriority.normal,
  status: TaskStatus.todo,
  tags: <String>[],
  repeatRule: RepeatRule.none,
);

final class MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read({
    required String accountId,
    required StoredKeyName keyName,
  }) async {
    final value = _values['$accountId:$keyName.name'];
    return value == null ? null : utf8.decode(base64Decode(value));
  }

  @override
  Future<void> write({
    required String accountId,
    required StoredKeyName keyName,
    required String value,
  }) async {
    _values['$accountId:$keyName.name'] = base64Encode(utf8.encode(value));
  }
}
