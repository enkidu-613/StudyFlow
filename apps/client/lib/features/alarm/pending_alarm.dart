enum PendingAlarmKind {
  focus,
  schedule,
  other,
}

final class PendingAlarm {
  const PendingAlarm({
    required this.id,
    required this.title,
    required this.text,
    required this.kind,
    this.entityId,
  });

  factory PendingAlarm.fromJson(Map<String, Object?> json) {
    final kindName = json['kind'];
    return PendingAlarm(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'StudyFlow 提醒',
      text: json['text'] as String? ?? '',
      kind: switch (kindName) {
        'focus' => PendingAlarmKind.focus,
        'schedule' => PendingAlarmKind.schedule,
        _ => PendingAlarmKind.other,
      },
      entityId: json['entity_id'] as String?,
    );
  }

  final String id;
  final String title;
  final String text;
  final PendingAlarmKind kind;
  final String? entityId;

  /// Whether this is the native alarm raised when a schedule occurrence ends.
  bool get isScheduleCompletion =>
      kind == PendingAlarmKind.schedule && id.contains(':end:');

  /// The start of the schedule occurrence represented by an end alarm.
  DateTime? get scheduleOccurrenceStart {
    if (!isScheduleCompletion) {
      return null;
    }
    final markerIndex = id.lastIndexOf(':end:');
    if (markerIndex < 0) {
      return null;
    }
    final milliseconds =
        int.tryParse(id.substring(markerIndex + ':end:'.length));
    if (milliseconds == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }
}
