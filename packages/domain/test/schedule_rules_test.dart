import 'package:studyflow_domain/src/focus_session.dart';
import 'package:studyflow_domain/src/schedule_block.dart';
import 'package:studyflow_domain/src/schedule_rules.dart';
import 'package:studyflow_domain/src/task.dart';
import 'package:test/test.dart';

void main() {
  test('locked schedule blocks cannot overlap', () {
    final result = ScheduleRules.validateNoOverlap(<ScheduleBlock>[
      block('08:00', '09:00', locked: true, id: 'locked-first'),
      block('08:30', '09:30', locked: true, id: 'locked-second'),
    ]);

    expect(result.single.code, 'locked_block_overlap');
    expect(result.single.blockIds, <String>['locked-first', 'locked-second']);
  });

  test('unlocked overlap violations are returned in deterministic order', () {
    final result = ScheduleRules.validateNoOverlap(<ScheduleBlock>[
      block('09:00', '10:00', id: 'third'),
      block('08:30', '09:30', id: 'second'),
      block('08:00', '09:15', id: 'first'),
    ]);

    expect(
      result
          .map((violation) => <Object>[violation.code, violation.blockIds])
          .toList(),
      <Object>[
        <Object>[
          'schedule_block_overlap',
          <String>['first', 'second'],
        ],
        <Object>[
          'schedule_block_overlap',
          <String>['first', 'third'],
        ],
        <Object>[
          'schedule_block_overlap',
          <String>['second', 'third'],
        ],
      ],
    );
  });

  test('adjacent schedule blocks do not overlap', () {
    final result = ScheduleRules.validateNoOverlap(<ScheduleBlock>[
      block('08:00', '09:00'),
      block('09:00', '10:00'),
    ]);

    expect(result, isEmpty);
  });

  test('schedule blocks reject an end that is not after the start', () {
    expect(
      () => block('08:00', '08:00'),
      throwsArgumentError,
    );
  });

  test('tasks require a positive estimated duration', () {
    expect(
      () => Task(
        id: 'task-1',
        title: 'Algebra',
        description: 'Complete the problem set.',
        estimatedMinutes: 0,
        priority: TaskPriority.high,
        status: TaskStatus.todo,
        tags: const <String>['math'],
        repeatRule: RepeatRule.none,
      ),
      throwsArgumentError,
    );
  });

  test('tasks preserve the requested repeat rule', () {
    final task = Task(
      id: 'task-1',
      title: 'Vocabulary review',
      description: 'Review flashcards.',
      estimatedMinutes: 20,
      priority: TaskPriority.normal,
      status: TaskStatus.todo,
      tags: const <String>['english'],
      repeatRule: RepeatRule.weekdays,
    );

    expect(task.repeatRule, RepeatRule.weekdays);
  });

  test('schedule blocks normalize instants to UTC for storage', () {
    final scheduled = block('08:00', '09:00');

    expect(scheduled.start, DateTime.utc(2026, 8, 11));
    expect(scheduled.end, DateTime.utc(2026, 8, 11, 1));
    expect(scheduled.start.isUtc, isTrue);
    expect(scheduled.end.isUtc, isTrue);
  });

  test('finishing a focus session returns a new finished session', () {
    final session = FocusSession(
      id: 'focus-1',
      taskId: 'task-1',
      startedAt: at('08:00'),
    );

    final finished = session.finish(
      at('08:25'),
      FocusCompletionMethod.manual,
    );

    expect(session.isFinished, isFalse);
    expect(session.endedAt, isNull);
    expect(finished, isNot(same(session)));
    expect(finished.isFinished, isTrue);
    expect(finished.endedAt, DateTime.utc(2026, 8, 11, 0, 25));
    expect(finished.completionMethod, FocusCompletionMethod.manual);
  });

  test('a finished focus session cannot be finished again', () {
    final finished = FocusSession(
      id: 'focus-1',
      taskId: 'task-1',
      startedAt: at('08:00'),
    ).finish(at('08:25'), FocusCompletionMethod.manual);

    expect(
      () => finished.finish(at('08:30'), FocusCompletionMethod.timer),
      throwsStateError,
    );
  });
}

ScheduleBlock block(
  String start,
  String end, {
  bool locked = false,
  String id = 'block',
}) =>
    ScheduleBlock(
      id: id,
      start: at(start),
      end: at(end),
      kind: ScheduleBlockKind.task,
      taskId: 'task-1',
      source: ScheduleBlockSource.manual,
      isLocked: locked,
    );

DateTime at(String time) => DateTime.parse('2026-08-11T$time:00+08:00');
