import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/ai/recommendation_screen.dart';
import 'package:studyflow/features/tasks/task_editor_screen.dart';
import 'package:studyflow/main.dart';
import 'package:studyflow_domain/domain.dart';

void main() {
  late Directory directory;
  late StudyFlowWorkspace workspace;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studyflow-app-test-');
    workspace = await StudyFlowWorkspace.openForTesting(
      accountId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
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

  testWidgets('wide window uses desktop navigation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(StudyFlowApp(workspace: workspace));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('narrow window keeps mobile navigation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(StudyFlowApp(workspace: workspace));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('Today opens the AI coach chat', (tester) async {
    await tester.pumpWidget(StudyFlowApp(workspace: workspace));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('today-ai-plan-button')));
    await tester.pumpAndSettle();

    expect(find.byType(RecommendationScreen), findsOneWidget);
    expect(find.byKey(const Key('ai-coach-input')), findsOneWidget);
  });

  testWidgets('task creation is saved to the local store', (tester) async {
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

  testWidgets('focus session starts and finishes into local storage',
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

    expect(find.text('Up to date'), findsWidgets);
    expect(find.text('Permissions'), findsOneWidget);
  });

  testWidgets('editing a medication plan preserves its identity',
      (tester) async {
    final plan = MedicationPlan(
      id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      name: '测试药',
      strength: '10 mg',
      dose: '1 片',
      frequency: MedicationFrequency.daily,
      reminderTimes: const <MedicationTime>[MedicationTime(hour: 9, minute: 0)],
      startDate: DateTime.utc(2026, 8, 17),
      enabled: true,
      createdAt: DateTime.utc(2026, 8, 17),
      updatedAt: DateTime.utc(2026, 8, 17),
    );
    await tester.runAsync(() async {
      await workspace.medications.savePlan(
        plan,
        write: await workspace.nextWrite(),
      );
    });
    await tester.pumpWidget(StudyFlowApp(workspace: workspace));
    await tester.pumpAndSettle();

    await tester.tap(find.text('药物'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试药'));
    await tester.pumpAndSettle();

    expect(find.text('编辑药物计划'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(2), '2 片');
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    final plans = await tester.runAsync(workspace.medications.listPlans);
    expect(plans, hasLength(1));
    expect(plans!.single.id, plan.id);
    expect(plans.single.dose, '2 片');
  });

  testWidgets('medication plan saves a two-day interval', (tester) async {
    await tester.pumpWidget(StudyFlowApp(workspace: workspace));
    await tester.pumpAndSettle();
    await tester.tap(find.text('药物'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '隔天药');
    await tester.enterText(find.byType(TextFormField).at(1), '10 mg');
    await tester.enterText(find.byType(TextFormField).at(2), '1 片');
    await tester.enterText(
        find.byKey(const Key('medication-interval-field')), '2');
    await tester.tap(find.text('确认并创建提醒'));
    await tester.pumpAndSettle();

    final plan =
        (await tester.runAsync(workspace.medications.listPlans))!.single;
    expect(plan.frequency, MedicationFrequency.everyNDays);
    expect(plan.intervalDays, 2);
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
