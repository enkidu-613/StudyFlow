import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/tasks/task_list_screen.dart';
import 'package:studyflow_domain/domain.dart';
import '../../helpers/l10n_test_app.dart';

void main() {
  late Directory directory;
  late StudyFlowWorkspace workspace;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studyflow-tasks-');
    workspace = await StudyFlowWorkspace.openForTesting(
      accountId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      baseDirectory: directory,
    );
  });

  tearDown(() async {
    await workspace.close();
    await directory.delete(recursive: true);
  });

  Future<void> seed(Task task) async {
    await workspace.tasks.save(task, write: await workspace.nextWrite());
  }

  Task task({
    required String id,
    required String title,
    TaskStatus status = TaskStatus.todo,
    TaskPriority priority = TaskPriority.normal,
  }) =>
      Task(
        id: id,
        title: title,
        description: '',
        estimatedMinutes: 25,
        priority: priority,
        status: status,
        tags: <String>[],
        repeatRule: RepeatRule.none,
      );

  testWidgets('checking a task completes it and unchecking restores it',
      (tester) async {
    await seed(task(id: 'aaaaaaaa-aaaa-4aaa-8aaa-000000000001', title: 'Algebra'));

    await pumpWithL10n(
      tester,
      TaskListScreen(workspace: workspace),
      locale: const Locale("en"),
    );
    await tester.pumpAndSettle();

    final checkbox = find.byType(Checkbox);
    expect(checkbox, findsOneWidget);
    expect(
      tester.widget<Checkbox>(checkbox).value,
      isFalse,
    );

    await tester.tap(checkbox);
    await tester.pumpAndSettle();

    final stored = await workspace.tasks.get('aaaaaaaa-aaaa-4aaa-8aaa-000000000001');
    expect(stored?.status, TaskStatus.completed);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    final restored = await workspace.tasks.get('aaaaaaaa-aaaa-4aaa-8aaa-000000000001');
    expect(restored?.status, TaskStatus.todo);
  });

  testWidgets('long-press menu marks a task in progress', (tester) async {
    await seed(task(id: 'aaaaaaaa-aaaa-4aaa-8aaa-000000000002', title: 'Physics'));

    await pumpWithL10n(
      tester,
      TaskListScreen(workspace: workspace),
      locale: const Locale("en"),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Physics'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-action-in-progress')), findsOneWidget);
    await tester.tap(find.byKey(const Key('task-action-in-progress')));
    await tester.pumpAndSettle();

    final stored = await workspace.tasks.get('aaaaaaaa-aaaa-4aaa-8aaa-000000000002');
    expect(stored?.status, TaskStatus.inProgress);
  });

  testWidgets('long-press delete confirms then removes the task',
      (tester) async {
    await seed(task(id: 'aaaaaaaa-aaaa-4aaa-8aaa-000000000003', title: 'Chemistry'));

    await pumpWithL10n(
      tester,
      TaskListScreen(workspace: workspace),
      locale: const Locale("en"),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Chemistry'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-action-delete')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('task-delete-dialog-confirm-button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('task-delete-dialog-confirm-button')));
    await tester.pumpAndSettle();

    expect(await workspace.tasks.get('aaaaaaaa-aaaa-4aaa-8aaa-000000000003'), isNull);
    expect(find.text('Chemistry'), findsNothing);
  });

  testWidgets('delete dialog cancel keeps the task', (tester) async {
    await seed(task(id: 'aaaaaaaa-aaaa-4aaa-8aaa-000000000004', title: 'Biology'));

    await pumpWithL10n(
      tester,
      TaskListScreen(workspace: workspace),
      locale: const Locale("en"),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Biology'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-action-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-delete-dialog-cancel-button')));
    await tester.pumpAndSettle();

    expect(await workspace.tasks.get('aaaaaaaa-aaaa-4aaa-8aaa-000000000004'), isNotNull);
    expect(find.text('Biology'), findsOneWidget);
  });

  testWidgets('filter chips narrow the visible tasks', (tester) async {
    await seed(
      task(id: 'aaaaaaaa-aaaa-4aaa-8aaa-000000000005', title: 'TodoTask', status: TaskStatus.todo),
    );
    await seed(
      task(
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-000000000006',
        title: 'DoingTask',
        status: TaskStatus.inProgress,
      ),
    );
    await seed(
      task(
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-000000000007',
        title: 'DoneTask',
        status: TaskStatus.completed,
      ),
    );

    await pumpWithL10n(
      tester,
      TaskListScreen(workspace: workspace),
      locale: const Locale("en"),
    );
    await tester.pumpAndSettle();

    expect(find.text('TodoTask'), findsOneWidget);
    expect(find.text('DoingTask'), findsOneWidget);
    expect(find.text('DoneTask'), findsOneWidget);

    await tester.tap(find.text('In progress'));
    await tester.pumpAndSettle();
    expect(find.text('DoingTask'), findsOneWidget);
    expect(find.text('TodoTask'), findsNothing);
    expect(find.text('DoneTask'), findsNothing);

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('DoneTask'), findsOneWidget);
    expect(find.text('DoingTask'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('TodoTask'), findsOneWidget);
    expect(find.text('DoingTask'), findsOneWidget);
    expect(find.text('DoneTask'), findsOneWidget);
  });

  testWidgets('empty filter shows hint and clear action', (tester) async {
    await seed(task(id: 'aaaaaaaa-aaaa-4aaa-8aaa-000000000008', title: 'OnlyTodo', status: TaskStatus.todo));

    await pumpWithL10n(
      tester,
      TaskListScreen(workspace: workspace),
      locale: const Locale("en"),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();

    expect(find.text('No tasks match the current filter'), findsOneWidget);
    await tester.tap(find.byKey(const Key('task-filter-clear')));
    await tester.pumpAndSettle();
    expect(find.text('OnlyTodo'), findsOneWidget);
  });
}
