import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/features/schedule/schedule_history.dart';
import 'package:studyflow_domain/domain.dart';

void main() {
  final now = DateTime.utc(2026, 8, 17, 12);

  ScheduleBlock block({
    required String id,
    required DateTime start,
    ScheduleRepeatRule repeatRule = ScheduleRepeatRule.none,
  }) =>
      ScheduleBlock(
        id: id,
        start: start,
        end: start.add(const Duration(hours: 1)),
        kind: ScheduleBlockKind.rest,
        taskId: null,
        source: ScheduleBlockSource.manual,
        isLocked: false,
        repeatRule: repeatRule,
      );

  test('past one-off blocks leave current while repeating blocks remain', () {
    final past = block(id: 'past', start: DateTime.utc(2026, 8, 17, 9));
    final future = block(id: 'future', start: DateTime.utc(2026, 8, 17, 13));
    final daily = block(
      id: 'daily',
      start: DateTime.utc(2026, 8, 16, 9),
      repeatRule: ScheduleRepeatRule.daily,
    );

    expect(currentBlocks(<ScheduleBlock>[past, future, daily], now),
        <ScheduleBlock>[future, daily]);
  });

  test('history joins feedback to the matching occurrence end', () {
    final scheduled = block(
      id: 'feedback',
      start: DateTime.utc(2026, 8, 16, 9),
    );
    final feedback = ScheduleFeedback(
      id: '11111111-1111-4111-8111-111111111111',
      scheduleBlockId: 'feedback',
      occurrenceStart: DateTime.utc(2026, 8, 16, 9),
      occurrenceEnd: DateTime.utc(2026, 8, 16, 10),
      kind: ScheduleBlockKind.rest,
      outcome: ScheduleFeedbackOutcome.notCompleted,
      reason: '临时不舒服',
      confirmedAt: DateTime.utc(2026, 8, 16, 10, 1),
    );

    final entries = historyEntries(
      blocks: <ScheduleBlock>[scheduled],
      feedback: <ScheduleFeedback>[feedback],
      from: DateTime.utc(2026, 8, 16),
      until: now,
    );

    expect(entries.single.feedback?.reason, '临时不舒服');
  });
}
