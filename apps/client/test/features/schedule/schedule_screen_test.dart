import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/schedule/schedule_screen.dart';
import 'package:studyflow_domain/domain.dart';
import '../../helpers/l10n_test_app.dart';

void main() {
  late Directory directory;
  late StudyFlowWorkspace workspace;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studyflow-schedule-');
    workspace = await StudyFlowWorkspace.openForTesting(
      accountId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      baseDirectory: directory,
    );
  });

  tearDown(() async {
    await workspace.close();
    await directory.delete(recursive: true);
  });

  Future<void> seed(ScheduleBlock block) async {
    await workspace.schedule.save(block, write: await workspace.nextWrite());
  }

  ScheduleBlock block({
    required String id,
    required DateTime start,
    DateTime? end,
    ScheduleBlockKind kind = ScheduleBlockKind.rest,
    bool isLocked = false,
  }) =>
      ScheduleBlock(
        id: id,
        start: start,
        end: end ?? start.add(const Duration(hours: 1)),
        kind: kind,
        taskId: null,
        source: ScheduleBlockSource.manual,
        isLocked: isLocked,
      );

  testWidgets('tapping a block opens the editor prefilled and editing works',
      (tester) async {
    final now = DateTime.now();
    final blockStart = DateTime(now.year, now.month, now.day, 9);
    await seed(
      block(
        id: 'bbbbbbbb-bbbb-4bbb-8bbb-000000000001',
        start: blockStart,
        kind: ScheduleBlockKind.sleep,
      ),
    );

    await pumpWithL10n(
      tester,
      ScheduleScreen(workspace: workspace),
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('schedule-block-bbbbbbbb-bbbb-4bbb-8bbb-000000000001')));
    await tester.pumpAndSettle();

    expect(find.text('Edit block'), findsOneWidget);
    expect(find.text('Sleep'), findsWidgets);

    await tester.tap(
      find.byType(DropdownButtonFormField<ScheduleBlockKind>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rest').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final stored = await workspace.schedule.get('bbbbbbbb-bbbb-4bbb-8bbb-000000000001');
    expect(stored?.kind, ScheduleBlockKind.rest);
  });

  testWidgets('swipe delete confirms and removes the block', (tester) async {
    final now = DateTime.now();
    await seed(
      block(
        id: 'bbbbbbbb-bbbb-4bbb-8bbb-000000000002',
        start: DateTime(now.year, now.month, now.day, 10),
      ),
    );

    await pumpWithL10n(
      tester,
      ScheduleScreen(workspace: workspace),
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('schedule-block-bbbbbbbb-bbbb-4bbb-8bbb-000000000002')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('block-delete-dialog-confirm-button')),
      findsOneWidget,
    );
    await tester
        .tap(find.byKey(const Key('block-delete-dialog-confirm-button')));
    await tester.pumpAndSettle();

    expect(await workspace.schedule.get('bbbbbbbb-bbbb-4bbb-8bbb-000000000002'), isNull);
    expect(find.byKey(const Key('schedule-block-bbbbbbbb-bbbb-4bbb-8bbb-000000000002')), findsNothing);
  });

  testWidgets('locked block cannot be edited and shows a hint',
      (tester) async {
    final now = DateTime.now();
    await seed(
      block(
        id: 'bbbbbbbb-bbbb-4bbb-8bbb-000000000003',
        start: DateTime(now.year, now.month, now.day, 11),
        isLocked: true,
      ),
    );

    await pumpWithL10n(
      tester,
      ScheduleScreen(workspace: workspace),
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('schedule-block-bbbbbbbb-bbbb-4bbb-8bbb-000000000003')));
    await tester.pumpAndSettle();

    expect(find.text('Edit block'), findsNothing);
    expect(find.text('This block is locked and cannot be edited'),
        findsOneWidget);
  });

  testWidgets('blocks are grouped by day in time order', (tester) async {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    await seed(
      block(
        id: 'bbbbbbbb-bbbb-4bbb-8bbb-000000000004',
        start: DateTime(now.year, now.month, now.day, 15),
      ),
    );
    await seed(
      block(
        id: 'bbbbbbbb-bbbb-4bbb-8bbb-000000000005',
        start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8),
      ),
    );

    await pumpWithL10n(
      tester,
      ScheduleScreen(workspace: workspace),
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
  });
}
