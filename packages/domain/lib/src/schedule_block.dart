enum ScheduleBlockKind { task, rest, sleep, breakTime }

enum ScheduleBlockSource { manual, generated, imported }

enum ScheduleRepeatRule { none, daily, weekdays, weekends, weekly }

final class ScheduleBlock {
  ScheduleBlock({
    required this.id,
    required DateTime start,
    required DateTime end,
    required this.kind,
    required this.taskId,
    required this.source,
    required this.isLocked,
    this.repeatRule = ScheduleRepeatRule.none,
  })  : start = start.toUtc(),
        end = end.toUtc() {
    if (!this.end.isAfter(this.start)) {
      throw ArgumentError.value(end, 'end', 'must be after start');
    }
  }

  factory ScheduleBlock.fromJson(Map<String, Object?> json) => ScheduleBlock(
        id: json['id']! as String,
        start: DateTime.parse(json['start']! as String),
        end: DateTime.parse(json['end']! as String),
        kind: ScheduleBlockKind.values.byName(json['kind']! as String),
        taskId: json['taskId'] as String?,
        source: ScheduleBlockSource.values.byName(json['source']! as String),
        isLocked: json['isLocked']! as bool,
        repeatRule: json['repeatRule'] == null
            ? ScheduleRepeatRule.none
            : ScheduleRepeatRule.values.byName(json['repeatRule']! as String),
      );

  final String id;
  final DateTime start;
  final DateTime end;
  final ScheduleBlockKind kind;
  final String? taskId;
  final ScheduleBlockSource source;
  final bool isLocked;
  final ScheduleRepeatRule repeatRule;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'kind': kind.name,
        'taskId': taskId,
        'source': source.name,
        'isLocked': isLocked,
        'repeatRule': repeatRule.name,
      };

  /// Returns the occurrences of this block's [repeatRule] starting at the
  /// first occurrence at or after [after] (exclusive), limited to [limit].
  Iterable<DateTime> occurrencesAfter(
    DateTime after, {
    int limit = 10,
  }) sync* {
    if (repeatRule == ScheduleRepeatRule.none) {
      if (start.isAfter(after)) {
        yield start;
      }
      return;
    }
    var candidate = start;
    var yielded = 0;
    while (yielded < limit) {
      if (candidate.isAfter(after)) {
        yield candidate;
        yielded += 1;
      }
      candidate = _nextOccurrence(candidate);
    }
  }

  DateTime _nextOccurrence(DateTime current) {
    final local = current.toLocal();
    final days = repeatRule == ScheduleRepeatRule.daily
        ? 1
        : repeatRule == ScheduleRepeatRule.weekly
            ? 7
            : 1;
    var next = DateTime(
      local.year,
      local.month,
      local.day + days,
      local.hour,
      local.minute,
    );
    if (repeatRule == ScheduleRepeatRule.weekdays ||
        repeatRule == ScheduleRepeatRule.weekends) {
      while (!_matchesWeekday(next.weekday)) {
        next = next.add(const Duration(days: 1));
      }
    }
    return next.toUtc();
  }

  bool _matchesWeekday(int weekday) => repeatRule == ScheduleRepeatRule.weekdays
      ? weekday <= DateTime.friday
      : weekday >= DateTime.saturday;
}
