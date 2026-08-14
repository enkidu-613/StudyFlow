import 'dart:async';

import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow_domain/domain.dart';

/// Rings an audible alarm on the device when a scheduled block starts.
///
/// Repeating blocks arm an alarm for each future occurrence. Relies on the
/// platform alarm support ([StudyFlowWorkspace.platform]); the scheduled
/// UNUserNotification stays in place as a background fallback for when the
/// app is not running.
final class ScheduleAlarmService {
  ScheduleAlarmService({
    required StudyFlowWorkspace workspace,
    bool enabled = true,
  })  : _workspace = workspace,
        _enabled = enabled {
    if (_enabled) {
      unawaited(resync());
    }
  }

  final StudyFlowWorkspace _workspace;
  final bool _enabled;
  final Map<String, Timer> _timers = <String, Timer>{};

  static const int _maxOccurrences = 14;

  /// Re-arms alarms for all future blocks, cancelling stale ones.
  Future<void> resync() async {
    final blocks = await _workspace.schedule.list();
    for (final block in blocks) {
      final title = _defaultTitle(block);
      _armOccurrences(
        block,
        title: title,
        text: _defaultText(block),
      );
    }
  }

  /// Arms or replaces the alarms for [block].
  void upsert(
    ScheduleBlock block, {
    required String title,
    required String text,
  }) {
    if (!_enabled) {
      return;
    }
    _cancelForBlock(block.id);
    _armOccurrences(block, title: title, text: text);
  }

  void _armOccurrences(
    ScheduleBlock block, {
    required String title,
    required String text,
  }) {
    final now = DateTime.now();
    var index = 0;
    for (final occurrence in block.occurrencesAfter(now, limit: _maxOccurrences)) {
      _armAt(
        block,
        occurrence: occurrence,
        index: index,
        title: title,
        text: text,
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
  }) {
    final delay = occurrence.difference(DateTime.now());
    _timers['${block.id}#$index'] = Timer(
      delay,
      () {
        _timers.remove('${block.id}#$index');
        unawaited(
          _workspace.platform
              .playAlarm(title: title, text: text)
              .then((_) {}, onError: (_) {}),
        );
      },
    );
  }

  /// Cancels all alarms for [blockId], if any.
  void cancel(String blockId) {
    _cancelForBlock(blockId);
  }

  void _cancelForBlock(String blockId) {
    final prefix = '$blockId#';
    for (final key in _timers.keys.toList(growable: false)) {
      if (key.startsWith(prefix)) {
        _timers.remove(key)?.cancel();
      }
    }
  }

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
  }
}
