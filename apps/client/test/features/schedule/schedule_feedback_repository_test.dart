import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/schedule/schedule_feedback_repository.dart';
import 'package:studyflow_domain/domain.dart';

void main() {
  late Directory directory;
  late StudyFlowWorkspace workspace;
  late ScheduleFeedbackRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studyflow-feedback-');
    workspace = await StudyFlowWorkspace.openForTesting(
      accountId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      baseDirectory: directory,
    );
    repository = workspace.scheduleFeedback;
  });

  tearDown(() async {
    await workspace.close();
    await directory.delete(recursive: true);
  });

  test('saving feedback queues a scoped schedule_feedback operation', () async {
    final feedback = ScheduleFeedback(
      id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      scheduleBlockId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      occurrenceStart: DateTime.utc(2026, 8, 17, 9),
      occurrenceEnd: DateTime.utc(2026, 8, 17, 10),
      kind: ScheduleBlockKind.task,
      outcome: ScheduleFeedbackOutcome.notCompleted,
      reason: '临时不舒服',
      confirmedAt: DateTime.utc(2026, 8, 17, 10, 5),
    );

    await repository.save(feedback, write: await workspace.nextWrite());

    expect(
      (await repository.findForOccurrence(
        scheduleBlockId: feedback.scheduleBlockId,
        occurrenceEnd: feedback.occurrenceEnd,
      ))!.reason,
      '临时不舒服',
    );
    expect(
      (await workspace.store.operations.pending(10)).single.entityType,
      'schedule_feedback',
    );
  });
}
