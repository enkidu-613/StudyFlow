import 'schedule_block.dart';

enum ScheduleFeedbackOutcome { completed, notCompleted }

/// A user's confirmation for one concrete occurrence of a schedule block.
///
/// It deliberately does not alter the recurring schedule template: a daily
/// block can therefore collect a separate feedback record for every day.
final class ScheduleFeedback {
  ScheduleFeedback({
    required this.id,
    required this.scheduleBlockId,
    required DateTime occurrenceStart,
    required DateTime occurrenceEnd,
    required this.kind,
    required this.outcome,
    String? reason,
    required DateTime confirmedAt,
  })  : occurrenceStart = occurrenceStart.toUtc(),
        occurrenceEnd = occurrenceEnd.toUtc(),
        reason = reason?.trim().isEmpty ?? true ? null : reason!.trim(),
        confirmedAt = confirmedAt.toUtc() {
    if (!this.occurrenceEnd.isAfter(this.occurrenceStart)) {
      throw ArgumentError.value(
        occurrenceEnd,
        'occurrenceEnd',
        'must be after occurrenceStart',
      );
    }
    if (outcome == ScheduleFeedbackOutcome.notCompleted &&
        this.reason == null) {
      throw ArgumentError.value(
        reason,
        'reason',
        'must be non-blank when not completed',
      );
    }
  }

  factory ScheduleFeedback.fromJson(Map<String, Object?> json) =>
      ScheduleFeedback(
        id: json['id']! as String,
        scheduleBlockId: json['scheduleBlockId']! as String,
        occurrenceStart: DateTime.parse(json['occurrenceStart']! as String),
        occurrenceEnd: DateTime.parse(json['occurrenceEnd']! as String),
        kind: ScheduleBlockKind.values.byName(json['kind']! as String),
        outcome: ScheduleFeedbackOutcome.values.byName(
          json['outcome']! as String,
        ),
        reason: json['reason'] as String?,
        confirmedAt: DateTime.parse(json['confirmedAt']! as String),
      );

  final String id;
  final String scheduleBlockId;
  final DateTime occurrenceStart;
  final DateTime occurrenceEnd;
  final ScheduleBlockKind kind;
  final ScheduleFeedbackOutcome outcome;
  final String? reason;
  final DateTime confirmedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'scheduleBlockId': scheduleBlockId,
        'occurrenceStart': occurrenceStart.toIso8601String(),
        'occurrenceEnd': occurrenceEnd.toIso8601String(),
        'kind': kind.name,
        'outcome': outcome.name,
        'reason': reason,
        'confirmedAt': confirmedAt.toIso8601String(),
      };
}
