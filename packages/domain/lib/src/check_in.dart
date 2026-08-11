final class CheckIn {
  CheckIn({
    required this.id,
    required DateTime recordedAt,
    required this.sleepMinutes,
    required this.sleepQuality,
    required this.energy,
    required this.mood,
    required this.feedback,
  }) : recordedAt = recordedAt.toUtc() {
    if (sleepMinutes < 0) {
      throw ArgumentError.value(
          sleepMinutes, 'sleepMinutes', 'must not be negative');
    }
    _validateRating(sleepQuality, 'sleepQuality');
    _validateRating(energy, 'energy');
    _validateRating(mood, 'mood');
  }

  factory CheckIn.fromJson(Map<String, Object?> json) => CheckIn(
        id: json['id']! as String,
        recordedAt: DateTime.parse(json['recordedAt']! as String),
        sleepMinutes: json['sleepMinutes']! as int,
        sleepQuality: json['sleepQuality']! as int,
        energy: json['energy']! as int,
        mood: json['mood']! as int,
        feedback: json['feedback']! as String,
      );

  final String id;
  final DateTime recordedAt;
  final int sleepMinutes;
  final int sleepQuality;
  final int energy;
  final int mood;
  final String feedback;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'recordedAt': recordedAt.toIso8601String(),
        'sleepMinutes': sleepMinutes,
        'sleepQuality': sleepQuality,
        'energy': energy,
        'mood': mood,
        'feedback': feedback,
      };

  static void _validateRating(int value, String fieldName) {
    if (value < 1 || value > 5) {
      throw ArgumentError.value(value, fieldName, 'must be between 1 and 5');
    }
  }
}
