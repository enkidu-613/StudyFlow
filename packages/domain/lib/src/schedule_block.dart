enum ScheduleBlockKind { task, rest, sleep, breakTime }

enum ScheduleBlockSource { manual, generated, imported }

final class ScheduleBlock {
  ScheduleBlock({
    required this.id,
    required DateTime start,
    required DateTime end,
    required this.kind,
    required this.taskId,
    required this.source,
    required this.isLocked,
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
      );

  final String id;
  final DateTime start;
  final DateTime end;
  final ScheduleBlockKind kind;
  final String? taskId;
  final ScheduleBlockSource source;
  final bool isLocked;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'kind': kind.name,
        'taskId': taskId,
        'source': source.name,
        'isLocked': isLocked,
      };
}
