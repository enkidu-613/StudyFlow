import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/features/schedule/schedule_completion_dialog.dart';
import 'package:studyflow/features/schedule/schedule_completion_service.dart';
import 'package:studyflow_domain/domain.dart';

void main() {
  testWidgets('unfinished completion requires a Chinese reason',
      (tester) async {
    final event = ScheduleCompletionEvent(
      block: ScheduleBlock(
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        start: DateTime.utc(2026, 8, 17, 9),
        end: DateTime.utc(2026, 8, 17, 10),
        kind: ScheduleBlockKind.task,
        taskId: null,
        source: ScheduleBlockSource.manual,
        isLocked: false,
      ),
      occurrenceStart: DateTime.utc(2026, 8, 17, 9),
      occurrenceEnd: DateTime.utc(2026, 8, 17, 10),
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => FilledButton(
          onPressed: () => showScheduleCompletionDialog(context, event),
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未完成'));
    await tester.tap(find.text('提交'));
    await tester.pump();

    expect(find.text('请填写未完成的原因'), findsOneWidget);
  });
}
