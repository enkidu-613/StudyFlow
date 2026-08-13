import 'dart:async';

import 'package:flutter/material.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/l10n/l10n_extension.dart';
import 'package:studyflow/util/uuid.dart';
import 'package:studyflow_domain/domain.dart';

final class FocusScreen extends StatefulWidget {
  const FocusScreen({required this.workspace, this.now, super.key});

  final StudyFlowWorkspace workspace;

  /// Clock used for the countdown; defaults to [DateTime.now].
  final DateTime Function()? now;

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

final class _FocusScreenState extends State<FocusScreen> {
  List<Task> _tasks = <Task>[];
  List<FocusSession> _sessions = <FocusSession>[];
  Object? _error;
  String? _taskId;
  DateTime? _sessionStartedAt;
  DateTime? _segmentStartedAt;
  Duration _accumulated = Duration.zero;
  Duration _target = Duration.zero;
  DateTime _now = DateTime.now();
  Timer? _timer;

  DateTime _currentTime() => (widget.now ?? DateTime.now)();

  bool get _running => _segmentStartedAt != null;

  Duration get _elapsed {
    final active = _segmentStartedAt;
    return _accumulated +
        (active == null ? Duration.zero : _now.difference(active));
  }

  Duration get _remaining {
    final remaining = _target - _elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final tasks = await widget.workspace.tasks.list();
      final sessions = await widget.workspace.focus.list();
      if (!mounted) {
        return;
      }
      setState(() {
        _tasks = tasks;
        _sessions = sessions;
        if (_taskId == null && tasks.isNotEmpty) {
          _taskId = tasks.first.id;
        }
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  Task? _selectedTask() => _tasks
      .where((task) => task.id == _taskId)
      .firstOrNull;

  Future<void> _start() async {
    final taskId = _taskId;
    final task = _selectedTask();
    if (taskId == null || task == null || _sessionStartedAt != null) {
      return;
    }
    final now = _currentTime();
    setState(() {
      _sessionStartedAt = now;
      _segmentStartedAt = now;
      _accumulated = Duration.zero;
      _target = Duration(minutes: task.estimatedMinutes);
      _now = now;
    });
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tick(),
    );
    final result = await widget.workspace.platform.startFocusSession(
      title: task.title,
    );
    if (mounted && !result.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  void _tick() {
    if (!mounted) {
      return;
    }
    setState(() => _now = _currentTime());
    if (_running && _target != Duration.zero && _elapsed >= _target) {
      unawaited(_autoFinish());
    }
  }

  Future<void> _autoFinish() async {
    final taskId = _taskId;
    if (taskId == null || _sessionStartedAt == null) {
      return;
    }
    final l10n = context.l10n;
    final task = _selectedTask();
    final title = task?.title ?? l10n.focusDefaultTitle;
    final alertTitle = l10n.focusCompletedTitle(title);
    final alertBody = l10n.focusCompletedBody;
    final snack = l10n.focusCompleted;
    final end = _currentTime();
    final session = FocusSession(
      id: newUuidV4(),
      taskId: taskId,
      startedAt: _sessionStartedAt!,
      endedAt: end,
      completionMethod: FocusCompletionMethod.timer,
    );
    await widget.workspace.focus.save(
      session,
      write: await widget.workspace.nextWrite(),
    );
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _sessionStartedAt = null;
        _segmentStartedAt = null;
        _accumulated = Duration.zero;
        _target = Duration.zero;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(snack)));
    }
    unawaited(
      widget.workspace.platform
          .playAlarm(title: alertTitle, text: alertBody)
          .then((_) {}, onError: (_) {}),
    );
    await _refresh();
  }

  void _pause() {
    final startedAt = _segmentStartedAt;
    if (startedAt == null) {
      return;
    }
    setState(() {
      _accumulated += _now.difference(startedAt);
      _segmentStartedAt = null;
    });
  }

  void _resume() {
    if (_sessionStartedAt == null || _running) {
      return;
    }
    setState(() {
      _segmentStartedAt = _currentTime();
      _now = _segmentStartedAt!;
    });
  }

  Future<void> _finish() async {
    final startedAt = _sessionStartedAt;
    if (startedAt == null || _taskId == null) {
      return;
    }
    final end = _currentTime();
    final session = FocusSession(
      id: newUuidV4(),
      taskId: _taskId!,
      startedAt: startedAt,
      endedAt: end,
      completionMethod: FocusCompletionMethod.manual,
    );
    await widget.workspace.focus.save(
      session,
      write: await widget.workspace.nextWrite(),
    );
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _sessionStartedAt = null;
        _segmentStartedAt = null;
        _accumulated = Duration.zero;
        _target = Duration.zero;
      });
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navFocus)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (_error != null)
              ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text('$_error'),
              ),
            DropdownButtonFormField<String>(
              initialValue: _taskId,
              decoration: InputDecoration(labelText: l10n.focusTaskLabel),
              items: <DropdownMenuItem<String>>[
                for (final task in _tasks)
                  DropdownMenuItem<String>(
                    value: task.id,
                    child: Text(task.title),
                  ),
              ],
              onChanged: _sessionStartedAt == null
                  ? (value) => setState(() => _taskId = value)
                  : null,
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                _target == Duration.zero
                    ? _formatDuration(_elapsed)
                    : _formatDuration(_remaining),
                style: Theme.of(context).textTheme.displayMedium,
              ),
            ),
            if (_target != Duration.zero)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _running
                        ? l10n.focusTimeRemaining
                        : l10n.focusPausedRemaining,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (_sessionStartedAt == null)
                  FilledButton.icon(
                    onPressed: _taskId == null ? null : _start,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(l10n.focusStart),
                  )
                else if (_running)
                  OutlinedButton.icon(
                    onPressed: _pause,
                    icon: const Icon(Icons.pause),
                    label: Text(l10n.focusPause),
                  )
                else
                  FilledButton.icon(
                    onPressed: _resume,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(l10n.focusResume),
                  ),
                if (_sessionStartedAt != null) ...<Widget>[
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _finish,
                    icon: const Icon(Icons.stop),
                    label: Text(l10n.focusFinish),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            Text(
              l10n.focusSessionsTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final session in _sessions)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(
                  _tasks
                          .where((task) => task.id == session.taskId)
                          .map((task) => task.title)
                          .firstOrNull ??
                      session.taskId,
                ),
                subtitle: Text(
                  '${_formatDateTime(session.startedAt)}  '
                  '${_formatDuration(session.endedAt!.difference(session.startedAt))}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
