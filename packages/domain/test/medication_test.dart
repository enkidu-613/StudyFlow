import 'package:studyflow_domain/domain.dart';
import 'package:test/test.dart';

void main() {
  MedicationPlan dailyPlan() => MedicationPlan(
        id: '11111111-1111-4111-8111-111111111111',
        name: '维生素 D',
        strength: '400 IU/片',
        dose: '1 片',
        frequency: MedicationFrequency.daily,
        reminderTimes: const <MedicationTime>[
          MedicationTime(hour: 9, minute: 30)
        ],
        startDate: DateTime.utc(2026, 8, 17),
        enabled: true,
        createdAt: DateTime.utc(2026, 8, 17),
        updatedAt: DateTime.utc(2026, 8, 17),
      );

  test('daily plan expands confirmed local reminder times', () {
    expect(
      dailyPlan().occurrencesBetween(
        DateTime.utc(2026, 8, 17),
        DateTime.utc(2026, 8, 19),
      ),
      <DateTime>[
        DateTime(2026, 8, 17, 9, 30).toUtc(),
        DateTime(2026, 8, 18, 9, 30).toUtc(),
      ],
    );
  });

  test('weekly plan only expands confirmed weekdays', () {
    final plan = MedicationPlan(
      id: '11111111-1111-4111-8111-111111111111',
      name: '测试药',
      strength: '10 mg',
      dose: '1 片',
      frequency: MedicationFrequency.weekly,
      reminderTimes: const <MedicationTime>[MedicationTime(hour: 8, minute: 0)],
      weekdays: const <int>{DateTime.monday, DateTime.friday},
      startDate: DateTime.utc(2026, 8, 17),
      enabled: true,
      createdAt: DateTime.utc(2026, 8, 17),
      updatedAt: DateTime.utc(2026, 8, 17),
    );
    expect(
      plan.occurrencesBetween(
        DateTime.utc(2026, 8, 17),
        DateTime.utc(2026, 8, 24),
      ),
      <DateTime>[
        DateTime(2026, 8, 17, 8).toUtc(),
        DateTime(2026, 8, 21, 8).toUtc(),
      ],
    );
  });

  test('every N days expands from the plan start date', () {
    final plan = MedicationPlan(
      id: '11111111-1111-4111-8111-111111111111',
      name: '隔天药',
      strength: '10 mg',
      dose: '1 片',
      frequency: MedicationFrequency.everyNDays,
      intervalDays: 2,
      reminderTimes: const <MedicationTime>[MedicationTime(hour: 8, minute: 0)],
      startDate: DateTime.utc(2026, 8, 17),
      enabled: true,
      createdAt: DateTime.utc(2026, 8, 17),
      updatedAt: DateTime.utc(2026, 8, 17),
    );
    expect(
      plan.occurrencesBetween(
        DateTime.utc(2026, 8, 17),
        DateTime.utc(2026, 8, 22),
      ),
      <DateTime>[
        DateTime(2026, 8, 17, 8).toUtc(),
        DateTime(2026, 8, 19, 8).toUtc(),
        DateTime(2026, 8, 21, 8).toUtc(),
      ],
    );
  });

  test('plan serializes without any raw medical order', () {
    final json = dailyPlan().toJson();
    expect(json.containsKey('rawMedicalOrder'), isFalse);
    expect(MedicationPlan.fromJson(json).dose, '1 片');
  });

  test('weekly plan requires weekdays and delayed record requires future time',
      () {
    expect(
      () => MedicationPlan(
        id: '11111111-1111-4111-8111-111111111111',
        name: '测试药',
        strength: '10 mg',
        dose: '1 片',
        frequency: MedicationFrequency.weekly,
        reminderTimes: const <MedicationTime>[
          MedicationTime(hour: 8, minute: 0)
        ],
        startDate: DateTime.utc(2026, 8, 17),
        enabled: true,
        createdAt: DateTime.utc(2026, 8, 17),
        updatedAt: DateTime.utc(2026, 8, 17),
      ),
      throwsArgumentError,
    );
    expect(
      () => MedicationDoseRecord(
        id: '22222222-2222-4222-8222-222222222222',
        medicationPlanId: '11111111-1111-4111-8111-111111111111',
        plannedAt: DateTime.utc(2026, 8, 17, 9),
        outcome: MedicationDoseOutcome.delayed,
        recordedAt: DateTime.utc(2026, 8, 17, 9),
        delayedUntil: DateTime.utc(2026, 8, 17, 9),
      ),
      throwsArgumentError,
    );
  });
}
