import 'dart:async';

import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow_domain/domain.dart';

/// Rings an audible alarm on the device when a scheduled block starts.
///
/// Relies on the platform alarm support ([StudyFlowWorkspace.platform]); the
/// scheduled UNUserNotification stays in place as a background fallback for
/// when the app is not running.
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

  /// Re-arms alarms for all future blocks, cancelling stale ones.
  Future<void> resync() async {
    final blocks = await _workspace.schedule.list();
    final now = DateTime.now();
    for (final block in blocks) {
      if (block.start.isAfter(now)) {
        final title = switch (block.kind) {
          ScheduleBlockKind.task => 'Task',
          ScheduleBlockKind.rest => 'Rest',
          ScheduleBlockKind.sleep => 'Sleep',
          ScheduleBlockKind.breakTime => 'Break',
        };
        _arm(
          block,
          title: title,
          text: block.start.toIso8601String(),
        );
      }
    }
  }

  /// Arms or replaces the alarm for [block].
  void upsert(ScheduleBlock block, {required String title, required String text}) {
    if (!_enabled) {
      return;
    }
    _timers.remove(block.id)?.cancel();
    if (!block.start.isAfter(DateTime.now())) {
      return;
    }
    _arm(block, title: title, text: text);
  }

  void _arm(
    ScheduleBlock block, {
    required String title,
    required String text,
  }) {
    _timers[block.id] = Timer(
      block.start.difference(DateTime.now()),
      () {
        _timers.remove(block.id);
        unawaited(
          _workspace.platform
              .playAlarm(title: title, text: text)
              .then((_) {}, onError: (_) {}),
        );
      },
    );
  }

  /// Cancels the alarm for [blockId], if any.
  void cancel(String blockId) {
    _timers.remove(blockId)?.cancel();
  }

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}
