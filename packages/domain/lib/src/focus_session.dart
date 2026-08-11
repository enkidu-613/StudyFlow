enum FocusCompletionMethod { manual, timer }

final class FocusSession {
  FocusSession({
    required this.id,
    required this.taskId,
    required DateTime startedAt,
    DateTime? endedAt,
    this.completionMethod,
  })  : startedAt = startedAt.toUtc(),
        endedAt = endedAt?.toUtc() {
    if (this.endedAt == null && completionMethod != null) {
      throw ArgumentError.value(
        completionMethod,
        'completionMethod',
        'requires an endedAt value',
      );
    }
    if (this.endedAt != null && completionMethod == null) {
      throw ArgumentError.value(
        completionMethod,
        'completionMethod',
        'is required when a session is finished',
      );
    }
    if (this.endedAt != null && !this.endedAt!.isAfter(this.startedAt)) {
      throw ArgumentError.value(endedAt, 'endedAt', 'must be after startedAt');
    }
  }

  factory FocusSession.fromJson(Map<String, Object?> json) => FocusSession(
        id: json['id']! as String,
        taskId: json['taskId']! as String,
        startedAt: DateTime.parse(json['startedAt']! as String),
        endedAt: json['endedAt'] == null
            ? null
            : DateTime.parse(json['endedAt']! as String),
        completionMethod: json['completionMethod'] == null
            ? null
            : FocusCompletionMethod.values
                .byName(json['completionMethod']! as String),
      );

  final String id;
  final String taskId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final FocusCompletionMethod? completionMethod;

  bool get isFinished => endedAt != null;

  FocusSession finish(DateTime end, FocusCompletionMethod completionMethod) {
    if (isFinished) {
      throw StateError('A finished focus session is append-only.');
    }
    return FocusSession(
      id: id,
      taskId: taskId,
      startedAt: startedAt,
      endedAt: end,
      completionMethod: completionMethod,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'taskId': taskId,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'completionMethod': completionMethod?.name,
      };
}
