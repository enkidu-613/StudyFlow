import 'dart:async';

import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow_domain/domain.dart';

/// Schedules medication reminders on the platform alarm service.
///
/// The native Android implementation persists each one-shot alarm, so these
/// reminders survive the app being backgrounded, terminated, or rebooted. A
/// short in-process timer is retained as a fallback for desktop/test targets
/// that do not expose a native alarm API.
final class MedicationAlarmService {
  MedicationAlarmService({
    required StudyFlowWorkspace workspace,
    bool enabled = true,
  })  : _workspace = workspace,
        _enabled = enabled {
    if (_enabled) {
      unawaited(_resyncSafely());
    }
  }

  static const Duration _armingHorizon = Duration(days: 30);
  static const int _maxOccurrences = 90;

  final StudyFlowWorkspace _workspace;
  final bool _enabled;
  final Map<String, Timer> _timers = <String, Timer>{};
  final Map<String, int> _generations = <String, int>{};

  Future<void> resync() async {
    if (!_enabled) {
      return;
    }
    final plans = await _workspace.medications.listPlans();
    final taken = await _takenOccurrences();
    for (final plan in plans) {
      await _cancelForPlan(plan.id);
      _armOccurrences(plan, taken);
    }
  }

  /// Startup reconciliation must never become an uncaught Flutter exception.
  ///
  /// Explicit callers can still await [resync] and handle an error. The
  /// constructor uses this best-effort wrapper because it runs in the
  /// background while the first screen is being built.
  Future<void> _resyncSafely() async {
    try {
      await resync();
    } on Object {
      // A later explicit sync or upsert can retry alarm registration. One
      // malformed/stale record must not take down the whole application.
    }
  }

  Future<void> upsert(MedicationPlan plan) async {
    if (!_enabled) {
      return;
    }
    await _cancelForPlan(plan.id);
    _armOccurrences(plan, await _takenOccurrences());
  }

  Future<void> cancel(String planId) => _cancelForPlan(planId);

  /// Groups the planned times already confirmed as taken by plan id.
  ///
  /// An occurrence with a taken dose record must stay silent: no ring, no
  /// vibration and no confirmation dialog when its time arrives.
  Future<Map<String, Set<DateTime>>> _takenOccurrences() async {
    final records = await _workspace.medications.listDoseRecords();
    final result = <String, Set<DateTime>>{};
    for (final record in records) {
      if (record.outcome != MedicationDoseOutcome.taken) {
        continue;
      }
      (result[record.medicationPlanId] ??= <DateTime>{})
          .add(record.plannedAt);
    }
    return result;
  }

  void _armOccurrences(MedicationPlan plan, Map<String, Set<DateTime>> taken) {
    final confirmed = taken[plan.id] ?? const <DateTime>{};
    final now = DateTime.now();
    final occurrences = plan.occurrencesBetween(
      now,
      now.add(_armingHorizon),
    )..sort();
    final generation = _generations[plan.id] ?? 0;
    for (var index = 0;
        index < occurrences.length && index < _maxOccurrences;
        index++) {
      final occurrence = occurrences[index];
      // 该时间点已确认服用：跳过注册，到点不响铃、不震动、不弹窗。
      if (confirmed.contains(occurrence)) {
        continue;
      }
      final alarmId = '${plan.id}#$index';
      unawaited(
        _scheduleOrFallbackSafely(
          plan: plan,
          alarmId: alarmId,
          occurrence: occurrence,
          generation: generation,
        ),
      );
    }
  }

  Future<void> _scheduleOrFallbackSafely({
    required MedicationPlan plan,
    required String alarmId,
    required DateTime occurrence,
    required int generation,
  }) async {
    try {
      await _scheduleOrFallback(
        plan: plan,
        alarmId: alarmId,
        occurrence: occurrence,
        generation: generation,
      );
    } on Object {
      // Platform scheduling is best effort. The UI remains usable and the
      // next explicit resync/upsert can retry this individual alarm.
    }
  }

  Future<void> _scheduleOrFallback({
    required MedicationPlan plan,
    required String alarmId,
    required DateTime occurrence,
    required int generation,
  }) async {
    final title = '${plan.name} · ${plan.dose}';
    final text = '现在是服药时间：${plan.name}（${plan.strength}），请按医嘱服用。';
    var nativeScheduled = false;
    try {
      final result = await _workspace.platform.scheduleReminder(
        title: title,
        at: occurrence,
        payload: text,
        identifier: alarmId,
        kind: 'medication',
        entityId: plan.id,
      );
      nativeScheduled = result.isSupported;
    } on Object {
      nativeScheduled = false;
    }

    if (!_isCurrent(plan.id, generation)) {
      if (nativeScheduled) {
        await _workspace.platform.cancelReminder(alarmId);
      }
      return;
    }
    if (nativeScheduled) {
      return;
    }

    final delay = occurrence.difference(DateTime.now());
    _timers[alarmId] = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        _timers.remove(alarmId);
        if (!_isCurrent(plan.id, generation)) {
          return;
        }
        unawaited(
          _workspace.platform.playAlarm(
            title: title,
            text: text,
            identifier: alarmId,
            kind: 'medication',
            entityId: plan.id,
          ),
        );
      },
    );
  }

  Future<void> _cancelForPlan(String planId) async {
    _generations[planId] = (_generations[planId] ?? 0) + 1;
    for (final alarmId in _timers.keys.toList(growable: false)) {
      if (alarmId.startsWith('$planId#') || alarmId.startsWith('$planId:')) {
        _timers.remove(alarmId)?.cancel();
      }
    }
    await _workspace.platform.cancelReminder(planId);
  }

  bool _isCurrent(String planId, int generation) =>
      _generations[planId] == generation;

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _generations.clear();
  }
}
