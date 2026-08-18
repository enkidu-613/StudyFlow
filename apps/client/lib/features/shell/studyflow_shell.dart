import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/alarm/pending_alarm.dart';
import 'package:studyflow/features/alarm/pending_alarm_dialog.dart';
import 'package:studyflow/features/schedule/schedule_completion_dialog.dart';
import 'package:studyflow/features/schedule/schedule_completion_service.dart';
import 'package:studyflow/l10n/app_localizations.dart';
import 'package:studyflow/l10n/l10n_extension.dart';
import 'package:studyflow/util/uuid.dart';
import 'package:studyflow_domain/domain.dart';

final class StudyFlowShell extends StatefulWidget {
  const StudyFlowShell({
    required this.workspace,
    required this.child,
    super.key,
  });

  final StudyFlowWorkspace workspace;
  final Widget child;

  @override
  State<StudyFlowShell> createState() => _StudyFlowShellState();
}

final class _StudyFlowShellState extends State<StudyFlowShell>
    with WidgetsBindingObserver {
  static const double _desktopBreakpoint = 900;

  StreamSubscription<ScheduleCompletionEvent>? _subscription;
  StreamSubscription<PendingAlarm>? _alarmSubscription;
  bool _alarmMonitoringStarted = false;
  Future<void> _dialogQueue = Future<void>.value();
  final Set<String> _queuedAlarmIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.workspace.completion.events.listen(_enqueue);
    // Clear the fixed start notification left by older builds. The actual
    // end-of-session alarm has its own id and is not affected by this.
    unawaited(
      widget.workspace.platform
          .cancelFocusSessionNotification()
          .then((_) {}, onError: (_) {}),
    );
    unawaited(_startAlarmMonitoring());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _alarmSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_startAlarmMonitoring());
      // An alarm can fire while the process is backgrounded. The event stream
      // is not guaranteed to be attached at that moment, so always reconcile
      // persisted native alarms when the UI becomes active again.
      if (_alarmMonitoringStarted) {
        unawaited(_refreshPendingAlarms());
      }
    }
  }

  Future<void> _startAlarmMonitoring() async {
    if (_alarmMonitoringStarted ||
        !await widget.workspace.platform.supportsAlarmEvents()) {
      return;
    }
    if (!mounted) return;
    _alarmMonitoringStarted = true;
    _alarmSubscription = widget.workspace.platform.alarmEvents.listen(
      _enqueueAlarm,
      onError: (_) {},
    );
    await _refreshPendingAlarms();
  }

  void _enqueue(ScheduleCompletionEvent event) {
    _dialogQueue = _dialogQueue.then((_) => _confirm(event));
  }

  Future<void> _refreshPendingAlarms() async {
    final alarms = await widget.workspace.platform.getPendingAlarms();
    for (final alarm in alarms) {
      _enqueueAlarm(alarm);
    }
  }

  void _enqueueAlarm(PendingAlarm alarm) {
    if (alarm.id.isEmpty || !_queuedAlarmIds.add(alarm.id)) {
      return;
    }
    _dialogQueue = _dialogQueue.then((_) async {
      try {
        await _confirmAlarm(alarm);
      } finally {
        _queuedAlarmIds.remove(alarm.id);
      }
    });
  }

  Future<void> _confirmAlarm(PendingAlarm alarm) async {
    if (!mounted) return;
    final target = switch (alarm.kind) {
      PendingAlarmKind.focus => '/focus',
      PendingAlarmKind.medication => '/medications',
      _ => '/schedule',
    };
    await _navigateTo(target);
    if (!mounted) return;

    final occurrenceStart = alarm.scheduleOccurrenceStart;
    final blockId = alarm.entityId;
    if (occurrenceStart != null && blockId != null) {
      await _confirmScheduleAlarm(
        alarm,
        blockId: blockId,
        occurrenceStart: occurrenceStart,
      );
      return;
    }

    final confirmed = await showPendingAlarmDialog(
      context,
      alarm,
      acknowledge: () => widget.workspace.platform.acknowledgeAlarm(alarm.id),
    );
    // A focus session also posts a separate informational notification with a
    // stable id. The alarm acknowledgement removes the ringing notification;
    // this removes the start notification as part of the same user action.
    if (confirmed == true) {
      await widget.workspace.platform.cancelFocusSessionNotification();
    }
  }

  Future<void> _navigateTo(String target) async {
    final currentPath = GoRouterState.of(context).uri.path;
    if (currentPath != target) {
      context.go(target);
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> _confirmScheduleAlarm(
    PendingAlarm alarm, {
    required String blockId,
    required DateTime occurrenceStart,
  }) async {
    final block = await widget.workspace.schedule.get(blockId);
    if (!mounted) return;
    if (block == null) {
      // Keep an orphaned alarm dismissible rather than leaving a permanent
      // ringing notification when its schedule was deleted elsewhere.
      await showPendingAlarmDialog(
        context,
        alarm,
        acknowledge: () => widget.workspace.platform.acknowledgeAlarm(alarm.id),
      );
      return;
    }

    final event = ScheduleCompletionEvent(
      block: block,
      occurrenceStart: occurrenceStart,
      occurrenceEnd: occurrenceStart.add(block.end.difference(block.start)),
    );
    if (await widget.workspace.scheduleFeedback.findForOccurrence(
          scheduleBlockId: event.block.id,
          occurrenceEnd: event.occurrenceEnd,
        ) !=
        null) {
      await widget.workspace.platform.acknowledgeAlarm(alarm.id);
      return;
    }
    if (!mounted) return;

    final draft = await showScheduleCompletionDialog(context, event);
    if (draft == null) return;
    await _saveScheduleFeedback(event, draft);
    await widget.workspace.platform.acknowledgeAlarm(alarm.id);
  }

  Future<void> _confirm(ScheduleCompletionEvent event) async {
    if (!mounted ||
        await widget.workspace.scheduleFeedback.findForOccurrence(
              scheduleBlockId: event.block.id,
              occurrenceEnd: event.occurrenceEnd,
            ) !=
            null) {
      return;
    }
    if (!mounted) return;
    final draft = await showScheduleCompletionDialog(context, event);
    if (draft == null) return;
    await _saveScheduleFeedback(event, draft);
  }

  Future<void> _saveScheduleFeedback(
    ScheduleCompletionEvent event,
    ScheduleCompletionDraft draft,
  ) async {
    await widget.workspace.scheduleFeedback.save(
      ScheduleFeedback(
        id: newUuidV4(),
        scheduleBlockId: event.block.id,
        occurrenceStart: event.occurrenceStart,
        occurrenceEnd: event.occurrenceEnd,
        kind: event.block.kind,
        outcome: draft.outcome,
        reason: draft.reason,
        confirmedAt: DateTime.now(),
      ),
      write: await widget.workspace.nextWrite(),
    );
    // Keep schedule completion confirmation consistent with focus
    // completion: no stale start/test notification should remain afterwards.
    await widget.workspace.platform.cancelFocusSessionNotification();
  }

  static const List<String> _paths = <String>[
    '/today',
    '/tasks',
    '/schedule',
    '/medications',
    '/focus',
    '/settings',
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final location = GoRouterState.of(context).uri.path;
    final selectedIndex = _paths.indexOf(location);
    final activeIndex = selectedIndex < 0 ? 0 : selectedIndex;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _desktopBreakpoint) {
          return _buildDesktopShell(
            context,
            activeIndex: activeIndex,
            l10n: l10n,
          );
        }
        return _buildMobileShell(
          context,
          activeIndex: activeIndex,
          l10n: l10n,
        );
      },
    );
  }

  Widget _buildMobileShell(
    BuildContext context, {
    required int activeIndex,
    required AppLocalizations l10n,
  }) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: activeIndex,
        onDestinationSelected: (index) => context.go(_paths[index]),
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.today_outlined),
            selectedIcon: const Icon(Icons.today),
            label: l10n.navToday,
          ),
          NavigationDestination(
            icon: const Icon(Icons.checklist_outlined),
            selectedIcon: const Icon(Icons.checklist),
            label: l10n.navTasks,
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            selectedIcon: const Icon(Icons.calendar_month),
            label: l10n.navSchedule,
          ),
          const NavigationDestination(
            icon: Icon(Icons.medication_outlined),
            selectedIcon: Icon(Icons.medication),
            label: '药物',
          ),
          NavigationDestination(
            icon: const Icon(Icons.timer_outlined),
            selectedIcon: const Icon(Icons.timer),
            label: l10n.navFocus,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopShell(
    BuildContext context, {
    required int activeIndex,
    required AppLocalizations l10n,
  }) {
    return Scaffold(
      body: Row(
        children: <Widget>[
          SafeArea(
            child: NavigationRail(
              extended: true,
              minExtendedWidth: 220,
              groupAlignment: -1,
              selectedIndex: activeIndex,
              onDestinationSelected: (index) => context.go(_paths[index]),
              leading: const SizedBox(height: 12),
              destinations: <NavigationRailDestination>[
                NavigationRailDestination(
                  icon: const Icon(Icons.today_outlined),
                  selectedIcon: const Icon(Icons.today),
                  label: Text(l10n.navToday),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.checklist_outlined),
                  selectedIcon: const Icon(Icons.checklist),
                  label: Text(l10n.navTasks),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.calendar_month_outlined),
                  selectedIcon: const Icon(Icons.calendar_month),
                  label: Text(l10n.navSchedule),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.medication_outlined),
                  selectedIcon: Icon(Icons.medication),
                  label: Text('药物'),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.timer_outlined),
                  selectedIcon: const Icon(Icons.timer),
                  label: Text(l10n.navFocus),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings),
                  label: Text(l10n.navSettings),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: SizedBox.expand(child: widget.child),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
