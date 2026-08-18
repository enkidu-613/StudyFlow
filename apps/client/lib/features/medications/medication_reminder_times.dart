import 'package:studyflow_domain/domain.dart';

/// Resizes the editable reminder-time draft without discarding values the
/// user has already entered.
List<MedicationTime> resizeMedicationReminderTimes(
  int count,
  List<MedicationTime> current,
) {
  if (count < 1) {
    throw ArgumentError.value(count, 'count', 'must be positive');
  }
  final result = <MedicationTime>[...current.take(count)];
  while (result.length < count) {
    final index = result.length;
    final previous =
        result.isEmpty ? const MedicationTime(hour: 9, minute: 0) : result.last;
    final minutes = previous.hour * 60 + previous.minute + 4 * 60;
    result.add(
      MedicationTime(
        hour: (minutes ~/ 60) % 24,
        minute: minutes % 60,
      ),
    );
    // Avoid an unused index warning while keeping the intent of one new slot
    // per requested daily dose explicit.
    assert(index >= 0);
  }
  return result;
}
