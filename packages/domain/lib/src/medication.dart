enum MedicationFrequency { daily, everyNDays, weekly }

enum MedicationDoseOutcome { taken, skipped, delayed }

/// A wall-clock reminder time, deliberately independent of Flutter UI types.
final class MedicationTime implements Comparable<MedicationTime> {
  const MedicationTime({required this.hour, required this.minute})
      : assert(hour >= 0 && hour <= 23),
        assert(minute >= 0 && minute <= 59);

  factory MedicationTime.fromJson(Map<String, Object?> json) => MedicationTime(
        hour: json['hour']! as int,
        minute: json['minute']! as int,
      );

  final int hour;
  final int minute;

  Map<String, Object?> toJson() => <String, Object?>{
        'hour': hour,
        'minute': minute,
      };

  @override
  int compareTo(MedicationTime other) =>
      (hour * 60 + minute).compareTo(other.hour * 60 + other.minute);

  @override
  bool operator ==(Object other) =>
      other is MedicationTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}

/// A user-confirmed reminder plan. Text fields are never clinically parsed.
final class MedicationPlan {
  MedicationPlan({
    required this.id,
    required String name,
    required String strength,
    required String dose,
    required this.frequency,
    this.intervalDays = 1,
    required List<MedicationTime> reminderTimes,
    Set<int> weekdays = const <int>{},
    required DateTime startDate,
    DateTime? endDate,
    required this.enabled,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? note,
  })  : name = _requiredText(name, 'name'),
        strength = _requiredText(strength, 'strength'),
        dose = _requiredText(dose, 'dose'),
        reminderTimes = List<MedicationTime>.unmodifiable(
          (List<MedicationTime>.from(reminderTimes)..sort()),
        ),
        weekdays = Set<int>.unmodifiable(weekdays),
        startDate = _dateOnly(startDate),
        endDate = endDate == null ? null : _dateOnly(endDate),
        createdAt = createdAt.toUtc(),
        updatedAt = updatedAt.toUtc(),
        note = _optionalText(note) {
    if (this.reminderTimes.isEmpty) {
      throw ArgumentError.value(
          reminderTimes, 'reminderTimes', 'must not be empty');
    }
    if (intervalDays < 1) {
      throw ArgumentError.value(
          intervalDays, 'intervalDays', 'must be positive');
    }
    if (this
        .weekdays
        .any((day) => day < DateTime.monday || day > DateTime.sunday)) {
      throw ArgumentError.value(
          weekdays, 'weekdays', 'must contain ISO weekdays');
    }
    if (frequency == MedicationFrequency.weekly && this.weekdays.isEmpty) {
      throw ArgumentError.value(
          weekdays, 'weekdays', 'is required for weekly plans');
    }
    if (frequency == MedicationFrequency.daily && this.weekdays.isNotEmpty) {
      throw ArgumentError.value(
          weekdays, 'weekdays', 'must be empty for daily plans');
    }
    if (frequency == MedicationFrequency.daily && intervalDays != 1) {
      throw ArgumentError.value(
          intervalDays, 'intervalDays', 'must be 1 for daily plans');
    }
    if (frequency == MedicationFrequency.weekly && intervalDays != 1) {
      throw ArgumentError.value(
          intervalDays, 'intervalDays', 'must be 1 for weekly plans');
    }
    if (this.endDate != null && this.endDate!.isBefore(this.startDate)) {
      throw ArgumentError.value(
          endDate, 'endDate', 'must not be before startDate');
    }
  }

  factory MedicationPlan.fromJson(Map<String, Object?> json) => MedicationPlan(
        id: json['id']! as String,
        name: json['name']! as String,
        strength: json['strength']! as String,
        dose: json['dose']! as String,
        frequency:
            MedicationFrequency.values.byName(json['frequency']! as String),
        intervalDays: json['intervalDays'] as int? ?? 1,
        reminderTimes: (json['reminderTimes']! as List<Object?>)
            .map((value) => MedicationTime.fromJson(
                (value! as Map).cast<String, Object?>()))
            .toList(),
        weekdays: (json['weekdays'] as List<Object?>? ?? const <Object?>[])
            .cast<int>()
            .toSet(),
        startDate: DateTime.parse(json['startDate']! as String),
        endDate: json['endDate'] == null
            ? null
            : DateTime.parse(json['endDate']! as String),
        enabled: json['enabled']! as bool,
        createdAt: DateTime.parse(json['createdAt']! as String),
        updatedAt: DateTime.parse(json['updatedAt']! as String),
        note: json['note'] as String?,
      );

  final String id;
  final String name;
  final String strength;
  final String dose;
  final MedicationFrequency frequency;
  final int intervalDays;
  final List<MedicationTime> reminderTimes;
  final Set<int> weekdays;
  final DateTime startDate;
  final DateTime? endDate;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? note;

  List<DateTime> occurrencesBetween(DateTime from, DateTime until) {
    if (!enabled || !until.isAfter(from)) return const <DateTime>[];
    final result = <DateTime>[];
    var day = _dateOnly(from.toLocal());
    final lastDay = _dateOnly(until.toLocal());
    while (!day.isAfter(lastDay)) {
      final dayUtc = DateTime.utc(day.year, day.month, day.day);
      final applies = !dayUtc.isBefore(startDate) &&
          (endDate == null || !dayUtc.isAfter(endDate!)) &&
          switch (frequency) {
            MedicationFrequency.daily => true,
            MedicationFrequency.everyNDays =>
              dayUtc.difference(startDate).inDays % intervalDays == 0,
            MedicationFrequency.weekly => weekdays.contains(day.weekday),
          };
      if (applies) {
        for (final time in reminderTimes) {
          final occurrence = DateTime(
            day.year,
            day.month,
            day.day,
            time.hour,
            time.minute,
          ).toUtc();
          if (!occurrence.isBefore(from.toUtc()) &&
              occurrence.isBefore(until.toUtc())) {
            result.add(occurrence);
          }
        }
      }
      day = day.add(const Duration(days: 1));
    }
    return result;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'strength': strength,
        'dose': dose,
        'frequency': frequency.name,
        'intervalDays': intervalDays,
        'reminderTimes': reminderTimes.map((time) => time.toJson()).toList(),
        'weekdays': weekdays.toList()..sort(),
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'enabled': enabled,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'note': note,
      };
}

final class MedicationDoseRecord {
  MedicationDoseRecord({
    required this.id,
    required this.medicationPlanId,
    required DateTime plannedAt,
    required this.outcome,
    required DateTime recordedAt,
    DateTime? delayedUntil,
    String? note,
  })  : plannedAt = plannedAt.toUtc(),
        recordedAt = recordedAt.toUtc(),
        delayedUntil = delayedUntil?.toUtc(),
        note = _optionalText(note) {
    if (outcome == MedicationDoseOutcome.delayed &&
        (this.delayedUntil == null ||
            !this.delayedUntil!.isAfter(this.plannedAt))) {
      throw ArgumentError.value(delayedUntil, 'delayedUntil',
          'must be after plannedAt for delayed records');
    }
    if (outcome != MedicationDoseOutcome.delayed && this.delayedUntil != null) {
      throw ArgumentError.value(
          delayedUntil, 'delayedUntil', 'is only valid for delayed records');
    }
  }

  factory MedicationDoseRecord.fromJson(Map<String, Object?> json) =>
      MedicationDoseRecord(
        id: json['id']! as String,
        medicationPlanId: json['medicationPlanId']! as String,
        plannedAt: DateTime.parse(json['plannedAt']! as String),
        outcome:
            MedicationDoseOutcome.values.byName(json['outcome']! as String),
        recordedAt: DateTime.parse(json['recordedAt']! as String),
        delayedUntil: json['delayedUntil'] == null
            ? null
            : DateTime.parse(json['delayedUntil']! as String),
        note: json['note'] as String?,
      );

  final String id;
  final String medicationPlanId;
  final DateTime plannedAt;
  final MedicationDoseOutcome outcome;
  final DateTime recordedAt;
  final DateTime? delayedUntil;
  final String? note;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'medicationPlanId': medicationPlanId,
        'plannedAt': plannedAt.toIso8601String(),
        'outcome': outcome.name,
        'recordedAt': recordedAt.toIso8601String(),
        'delayedUntil': delayedUntil?.toIso8601String(),
        'note': note,
      };
}

String _requiredText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty)
    throw ArgumentError.value(value, name, 'must not be blank');
  return normalized;
}

String? _optionalText(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

DateTime _dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
