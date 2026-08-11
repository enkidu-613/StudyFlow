import 'dart:async';

import 'package:flutter/material.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/util/uuid.dart';
import 'package:studyflow_domain/domain.dart';

final class FocusScreen extends StatefulWidget {
  const FocusScreen({required this.workspace, super.key});

  final StudyFlowWorkspace workspace;

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
  DateTime _now = DateTime.now();
  Timer? _timer;

  bool get _running => _segmentStartedAt != null;

  Duration get _elapsed {
    final active = _segmentStartedAt;
    return _accumulated +
        (active == null ? Duration.zero : _now.difference(active));
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

  Future<void> _start() async {
    final taskId = _taskId;
    if (taskId == null || _sessionStartedAt != null) {
      return;
    }
    final now = DateTime.now();
    setState(() {
      _sessionStartedAt = now;
      _segmentStartedAt = now;
      _accumulated = Duration.zero;
      _now = now;
    });
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
    final taskTitle = _tasks
        .where((task) => task.id == taskId)
        .map((task) => task.title)
        .firstOrNull;
    final result = await widget.workspace.platform.startFocusSession(
      title: taskTitle ?? 'StudyFlow focus',
    );
    if (mounted && !result.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
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
      _segmentStartedAt = DateTime.now();
      _now = _segmentStartedAt!;
    });
  }

  Future<void> _finish() async {
    final startedAt = _sessionStartedAt;
    if (startedAt == null || _taskId == null) {
      return;
    }
    final end = DateTime.now();
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
      });
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Focus')),
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
              decoration: const InputDecoration(labelText: 'Task'),
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
                _formatDuration(_elapsed),
                style: Theme.of(context).textTheme.displayMedium,
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
                    label: const Text('Start'),
                  )
                else if (_running)
                  OutlinedButton.icon(
                    onPressed: _pause,
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _resume,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                  ),
                if (_sessionStartedAt != null) ...<Widget>[
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _finish,
                    icon: const Icon(Icons.stop),
                    label: const Text('Finish'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            const Text('Sessions',
                style: TextStyle(fontWeight: FontWeight.bold)),
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
