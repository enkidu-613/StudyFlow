import 'dart:async';

import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow_domain/domain.dart';

/// Rings an audible alarm on the device when a scheduled block starts and ends.
///
/// Repeating blocks arm an alarm for each future occurrence. The platform
/// alarm is the primary path so reminders survive the app being backgrounded
/// or terminated; the in-process timer is only a fallback when the platform
/// cannot schedule an alarm.
final class ScheduleAlarmService {
  ScheduleAlarmService({
    required StudyFlowWorkspace workspace,
    bool enabled = true,
  })  : _workspace = workspace,
        _enabled = enabled {
    if (_enabled) {
      unawaited(_resyncSafely());
    }
  }

  final StudyFlowWorkspace _workspace;
  final bool _enabled;
  final Map<String, Timer> _timers = <String, Timer>{};
  final Map<String, int> _generations = <String, int>{};

  static const int _maxOccurrences = 14;
  static const Duration _armingHorizon = Duration(days: 14);

  /// Re-arms alarms for all future blocks, cancelling stale ones.
  Future<void> resync() async {
    final blocks = await _workspace.schedule.list();
    for (final block in blocks) {
      await _cancelForBlock(block.id);
      final title = _defaultTitle(block);
      _armOccurrences(
        block,
        title: title,
        text: _defaultText(block),
      );
    }
  }

  /// Startup reconciliation must never become an uncaught Flutter exception.
  ///
  /// The explicit [resync] method remains awaitable for callers such as sync
  /// and settings, where the caller can surface an error to the user. This
  /// wrapper is only for the best-effort constructor startup task.
  Future<void> _resyncSafely() async {
    try {
      await resync();
    } on Object {
      // A later explicit sync or upsert can retry alarm registration. One
      // malformed/stale record must not take down the whole application.
    }
  }

  /// Arms or replaces the alarms for [block].
  Future<void> upsert(
    ScheduleBlock block, {
    required String title,
    required String text,
  }) async {
    if (!_enabled) {
      return;
    }
    await _cancelForBlock(block.id);
    _armOccurrences(block, title: title, text: text);
  }

  void _armOccurrences(
    ScheduleBlock block, {
    required String title,
    required String text,
  }) {
    final now = DateTime.now();
    final occurrenceByMillis = <int, DateTime>{};
    for (final occurrence in block.occurrencesOverlapping(
      now,
      now.add(_armingHorizon),
      limit: _maxOccurrences,
    )) {
      occurrenceByMillis[occurrence.millisecondsSinceEpoch] = occurrence;
    }
    for (final occurrence
        in block.occurrencesAfter(now, limit: _maxOccurrences)) {
      occurrenceByMillis[occurrence.millisecondsSinceEpoch] = occurrence;
    }
    final occurrences = occurrenceByMillis.values.toList()
      ..sort((left, right) => left.compareTo(right));
    var index = 0;
    for (final occurrence in occurrences) {
      _armAt(
        block,
        occurrence: occurrence,
        index: index,
        title: title,
        text: text,
        scheduleStart: occurrence.isAfter(now),
      );
      index += 1;
    }
  }

  void _armAt(
    ScheduleBlock block, {
    required DateTime occurrence,
    required int index,
    required String title,
    required String text,
    required bool scheduleStart,
  }) {
    final generation = _generations[block.id] ?? 0;
    if (scheduleStart) {
      final alarmId = '${block.id}#$index';
      final delay = occurrence.difference(DateTime.now());
      // Wait for the native result before arming the in-process fallback. The
      // old implementation started both paths at once, so a slow native call
      // could make the fallback ring and then let AlarmManager ring again.
      unawaited(
        _scheduleOrFallbackSafely(
          block: block,
          alarmId: alarmId,
          occurrence: occurrence,
          delay: delay,
          title: title,
          text: text,
          generation: generation,
        ),
      );
    }
    final end = occurrence.add(block.end.difference(block.start));
    final endAlarmId =
        '${block.id}:end:${occurrence.toUtc().millisecondsSinceEpoch}';
    final endDelay = end.difference(DateTime.now());
    unawaited(
      _scheduleOrFallbackSafely(
        block: block,
        alarmId: endAlarmId,
        occurrence: end,
        delay: endDelay,
        title: '$title结束',
        text: '$text · 日程已结束，请确认',
        generation: generation,
        notifyCompletionWhenUnsupported: true,
      ),
    );
  }

  Future<void> _scheduleOrFallbackSafely({
    required ScheduleBlock block,
    required String alarmId,
    required DateTime occurrence,
    required Duration delay,
    required String title,
    required String text,
    required int generation,
    bool notifyCompletionWhenUnsupported = false,
  }) async {
    try {
      await _scheduleOrFallback(
        block: block,
        alarmId: alarmId,
        occurrence: occurrence,
        delay: delay,
        title: title,
        text: text,
        generation: generation,
        notifyCompletionWhenUnsupported: notifyCompletionWhenUnsupported,
      );
    } on Object {
      // Platform scheduling is best effort. The UI remains usable and the
      // next explicit resync/upsert can retry this individual alarm.
    }
  }

  /// Cancels all alarms for [blockId], if any.
  Future<void> cancel(String blockId) {
    return _cancelForBlock(blockId);
  }

  Future<void> _cancelForBlock(String blockId) async {
    _generations[blockId] = (_generations[blockId] ?? 0) + 1;
    final startPrefix = '$blockId#';
    final endPrefix = '$blockId:';
    for (final key in _timers.keys.toList(growable: false)) {
      if (key.startsWith(startPrefix) || key.startsWith(endPrefix)) {
        _timers.remove(key)?.cancel();
      }
    }
    await _workspace.platform.cancelReminder(blockId);
  }

  Future<void> _scheduleOrFallback({
    required ScheduleBlock block,
    required String alarmId,
    required DateTime occurrence,
    required Duration delay,
    required String title,
    required String text,
    required int generation,
    bool notifyCompletionWhenUnsupported = false,
  }) async {
    var nativeScheduled = false;
    try {
      final result = await _workspace.platform.scheduleReminder(
        title: title,
        at: occurrence,
        payload: text,
        identifier: alarmId,
        kind: 'schedule',
        entityId: block.id,
      );
      nativeScheduled = result.isSupported;
    } on Object {
      nativeScheduled = false;
    }

    if (!_isCurrent(block.id, generation)) {
      if (nativeScheduled) {
        await _workspace.platform.cancelReminder(alarmId);
      }
      return;
    }
    if (nativeScheduled) {
      return;
    }

    _timers[alarmId] = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        _timers.remove(alarmId);
        if (!_isCurrent(block.id, generation)) {
          return;
        }
        unawaited(
          _workspace.platform
              .playAlarm(
            title: title,
            text: text,
            identifier: alarmId,
            kind: 'schedule',
            entityId: block.id,
          )
              .then((result) {
            if (notifyCompletionWhenUnsupported && !result.isSupported) {
              _workspace.completion.notifyEnded(
                block: block,
                occurrenceStart: occurrence.subtract(
                  block.end.difference(block.start),
                ),
              );
            }
          }, onError: (_) {
            if (notifyCompletionWhenUnsupported) {
              _workspace.completion.notifyEnded(
                block: block,
                occurrenceStart: occurrence.subtract(
                  block.end.difference(block.start),
                ),
              );
            }
          }),
        );
      },
    );
  }

  bool _isCurrent(String blockId, int generation) =>
      _generations[blockId] == generation;

  String _defaultTitle(ScheduleBlock block) => switch (block.kind) {
        ScheduleBlockKind.task => 'Task',
        ScheduleBlockKind.rest => 'Rest',
        ScheduleBlockKind.sleep => 'Sleep',
        ScheduleBlockKind.breakTime => 'Break',
      };

  String _defaultText(ScheduleBlock block) => block.start.toIso8601String();

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _generations.clear();
  }
}
