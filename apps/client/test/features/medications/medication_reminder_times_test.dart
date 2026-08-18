import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/features/medications/medication_reminder_times.dart';
import 'package:studyflow_domain/domain.dart';

void main() {
  test('resizing reminder times preserves existing values and fills new slots',
      () {
    final resized = resizeMedicationReminderTimes(
      3,
      const <MedicationTime>[
        MedicationTime(hour: 8, minute: 30),
        MedicationTime(hour: 13, minute: 0),
      ],
    );

    expect(resized, <MedicationTime>[
      const MedicationTime(hour: 8, minute: 30),
      const MedicationTime(hour: 13, minute: 0),
      const MedicationTime(hour: 17, minute: 0),
    ]);
  });

  test('resizing to one reminder drops additional times', () {
    expect(
      resizeMedicationReminderTimes(
        1,
        const <MedicationTime>[
          MedicationTime(hour: 8, minute: 30),
          MedicationTime(hour: 13, minute: 0),
        ],
      ),
      <MedicationTime>[const MedicationTime(hour: 8, minute: 30)],
    );
  });
}
