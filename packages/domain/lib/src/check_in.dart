final class CheckIn {
  CheckIn({
    required this.id,
    required DateTime recordedAt,
    required this.sleepMinutes,
    required this.sleepQuality,
    required this.energy,
    required this.mood,
    required this.feedback,
    DateTime? sleepStartedAt,
    DateTime? sleepEndedAt,
  })  : recordedAt = recordedAt.toUtc(),
        sleepStartedAt = sleepStartedAt?.toUtc(),
        sleepEndedAt = sleepEndedAt?.toUtc() {
    if (sleepMinutes < 0) {
      throw ArgumentError.value(
          sleepMinutes, 'sleepMinutes', 'must not be negative');
    }
    _validateRating(sleepQuality, 'sleepQuality');
    _validateRating(energy, 'energy');
    _validateRating(mood, 'mood');
    if ((this.sleepStartedAt == null) != (this.sleepEndedAt == null)) {
      throw ArgumentError('sleep start and end must be provided together');
    }
    if (this.sleepStartedAt != null &&
        !this.sleepEndedAt!.isAfter(this.sleepStartedAt!)) {
      throw ArgumentError('sleep end must be after sleep start');
    }
  }

  factory CheckIn.fromJson(Map<String, Object?> json) => CheckIn(
        id: json['id']! as String,
        recordedAt: DateTime.parse(json['recordedAt']! as String),
        sleepMinutes: json['sleepMinutes']! as int,
        sleepQuality: json['sleepQuality']! as int,
        energy: json['energy']! as int,
        mood: json['mood']! as int,
        feedback: json['feedback']! as String,
        sleepStartedAt: json['sleepStartedAt'] == null
            ? null
            : DateTime.parse(json['sleepStartedAt']! as String),
        sleepEndedAt: json['sleepEndedAt'] == null
            ? null
            : DateTime.parse(json['sleepEndedAt']! as String),
      );

  final String id;
  final DateTime recordedAt;
  final int sleepMinutes;
  final int sleepQuality;
  final int energy;
  final int mood;
  final String feedback;
  final DateTime? sleepStartedAt;
  final DateTime? sleepEndedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'recordedAt': recordedAt.toIso8601String(),
        'sleepMinutes': sleepMinutes,
        'sleepQuality': sleepQuality,
        'energy': energy,
        'mood': mood,
        'feedback': feedback,
        'sleepStartedAt': sleepStartedAt?.toIso8601String(),
        'sleepEndedAt': sleepEndedAt?.toIso8601String(),
      };

  static void _validateRating(int value, String fieldName) {
    if (value < 1 || value > 5) {
      throw ArgumentError.value(value, fieldName, 'must be between 1 and 5');
    }
  }
}
