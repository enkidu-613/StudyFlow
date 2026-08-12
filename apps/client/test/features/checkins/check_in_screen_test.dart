import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/checkins/check_in_screen.dart';
import '../../helpers/l10n_test_app.dart';

void main() {
  late Directory directory;
  late StudyFlowWorkspace workspace;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studyflow-checkin-');
    workspace = await StudyFlowWorkspace.openForTesting(
      accountId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      baseDirectory: directory,
    );
  });

  tearDown(() async {
    await workspace.close();
    await directory.delete(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await pumpWithL10n(
      tester,
      CheckInScreen(workspace: workspace),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows an empty state before any check-in', (tester) async {
    await pumpScreen(tester);

    expect(find.text('还没有打卡记录'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('saving a check-in persists it and updates the list',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('check-in-sleep-field')),
      '450',
    );
    await tester.enterText(
      find.byKey(const Key('check-in-feedback-field')),
      'Slept well',
    );
    await tester.tap(find.byKey(const Key('save-check-in-button')));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(find.text('睡眠 450 分钟 · 精力 3'), findsOneWidget);
    expect(find.text('Slept well'), findsNothing);

    final saved = await tester.runAsync(workspace.checkIns.list);
    expect(saved, hasLength(1));
    expect(saved!.single.sleepMinutes, 450);
    expect(saved.single.feedback, 'Slept well');
  });

  testWidgets('invalid sleep minutes shows an inline error', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('check-in-sleep-field')),
      'abc',
    );
    await tester.tap(find.byKey(const Key('save-check-in-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('睡眠时长必须是非负数字'),
      findsOneWidget,
    );
    expect(await tester.runAsync(workspace.pendingCount), 0);
  });

  testWidgets('cancelling the dialog saves nothing', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('还没有打卡记录'), findsOneWidget);
    expect(await tester.runAsync(workspace.pendingCount), 0);
  });
}
