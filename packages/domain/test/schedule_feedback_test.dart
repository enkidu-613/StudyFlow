import 'package:studyflow_domain/domain.dart';
import 'package:test/test.dart';

void main() {
  final start = DateTime.utc(2026, 8, 17, 9);
  final end = DateTime.utc(2026, 8, 17, 10);

  test('unfinished feedback requires a non-blank reason', () {
    expect(
      () => ScheduleFeedback(
        id: '11111111-1111-4111-8111-111111111111',
        scheduleBlockId: '22222222-2222-4222-8222-222222222222',
        occurrenceStart: start,
        occurrenceEnd: end,
        kind: ScheduleBlockKind.task,
        outcome: ScheduleFeedbackOutcome.notCompleted,
        confirmedAt: end,
      ),
      throwsArgumentError,
    );
  });

  test('feedback JSON preserves a submitted unfinished reason', () {
    final feedback = ScheduleFeedback(
      id: '11111111-1111-4111-8111-111111111111',
      scheduleBlockId: '22222222-2222-4222-8222-222222222222',
      occurrenceStart: start,
      occurrenceEnd: end,
      kind: ScheduleBlockKind.task,
      outcome: ScheduleFeedbackOutcome.notCompleted,
      reason: '临时不舒服',
      confirmedAt: end.add(const Duration(minutes: 2)),
    );

    expect(ScheduleFeedback.fromJson(feedback.toJson()).reason, '临时不舒服');
    expect(ScheduleFeedback.fromJson(feedback.toJson()).occurrenceEnd, end);
  });

  test('daily block includes an instance that overlaps the requested range',
      () {
    final block = ScheduleBlock(
      id: '22222222-2222-4222-8222-222222222222',
      start: start,
      end: end,
      kind: ScheduleBlockKind.rest,
      taskId: null,
      source: ScheduleBlockSource.manual,
      isLocked: false,
      repeatRule: ScheduleRepeatRule.daily,
    );

    expect(
      block.occurrencesOverlapping(
        DateTime.utc(2026, 8, 18, 9, 30),
        DateTime.utc(2026, 8, 18, 10, 30),
      ),
      <DateTime>[DateTime.utc(2026, 8, 18, 9)],
    );
  });
}
