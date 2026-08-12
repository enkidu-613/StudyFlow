import 'package:flutter/material.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/l10n/l10n_extension.dart';
import 'package:studyflow/util/uuid.dart';
import 'package:studyflow_domain/domain.dart';

final class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({required this.workspace, super.key});

  final StudyFlowWorkspace workspace;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

final class _ScheduleScreenState extends State<ScheduleScreen> {
  List<ScheduleBlock> _blocks = <ScheduleBlock>[];
  List<Task> _tasks = <Task>[];
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final blocks = await widget.workspace.schedule.list();
      final tasks = await widget.workspace.tasks.list();
      if (!mounted) {
        return;
      }
      setState(() {
        _blocks = blocks;
        _tasks = tasks;
        _error = null;
        _loading = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _openEditor() async {
    final saved = await showModalBottomSheet<ScheduleBlock>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ScheduleBlockEditor(
        workspace: widget.workspace,
        tasks: _tasks,
      ),
    );
    if (saved != null) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSchedule)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: <Widget>[
                  if (_error != null)
                    ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text('$_error'),
                    ),
                  for (final block in _blocks)
                    ListTile(
                      leading: Icon(_iconFor(block.kind)),
                      title: Text(_titleFor(block)),
                      subtitle: Text(
                        '${_format(block.start)} - ${_format(block.end)}',
                      ),
                      trailing: block.isLocked
                          ? const Icon(Icons.lock_outline)
                          : null,
                    ),
                  if (_blocks.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(child: Text(l10n.scheduleEmpty)),
                    ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openEditor,
        tooltip: l10n.blockNew,
        child: const Icon(Icons.add),
      ),
    );
  }

  IconData _iconFor(ScheduleBlockKind kind) => switch (kind) {
        ScheduleBlockKind.task => Icons.school_outlined,
        ScheduleBlockKind.rest => Icons.self_improvement,
        ScheduleBlockKind.sleep => Icons.bedtime_outlined,
        ScheduleBlockKind.breakTime => Icons.coffee_outlined,
      };

  String _titleFor(ScheduleBlock block) =>
      block.kind == ScheduleBlockKind.task && block.taskId != null
          ? _tasks
                  .where((task) => task.id == block.taskId)
                  .map((task) => task.title)
                  .firstOrNull ??
              block.kind.name
          : block.kind.name;

  String _format(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

final class _ScheduleBlockEditor extends StatefulWidget {
  const _ScheduleBlockEditor({
    required this.workspace,
    required this.tasks,
  });

  final StudyFlowWorkspace workspace;
  final List<Task> tasks;

  @override
  State<_ScheduleBlockEditor> createState() => _ScheduleBlockEditorState();
}

final class _ScheduleBlockEditorState extends State<_ScheduleBlockEditor> {
  ScheduleBlockKind _kind = ScheduleBlockKind.task;
  late DateTime _start;
  late DateTime _end;
  String? _taskId;
  bool _locked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = now;
    _end = now.add(const Duration(hours: 1));
  }

  Future<void> _pickStart() async {
    final picked = await _pickDateTime(_start);
    if (picked != null) {
      setState(() => _start = picked);
    }
  }

  Future<void> _pickEnd() async {
    final picked = await _pickDateTime(_end);
    if (picked != null) {
      setState(() => _end = picked);
    }
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null) {
      return null;
    }
    if (!mounted) {
      return null;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) {
      return null;
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _save() async {
    if (!_end.isAfter(_start)) {
      setState(() => _error = context.l10n.blockEndAfterStart);
      return;
    }
    final block = ScheduleBlock(
      id: newUuidV4(),
      start: _start,
      end: _end,
      kind: _kind,
      taskId: _kind == ScheduleBlockKind.task ? _taskId : null,
      source: ScheduleBlockSource.manual,
      isLocked: _locked,
    );
    await widget.workspace.schedule.save(
      block,
      write: await widget.workspace.nextWrite(),
    );
    if (mounted) {
      Navigator.of(context).pop(block);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l10n.blockNew, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 16),
          DropdownButtonFormField<ScheduleBlockKind>(
            initialValue: _kind,
            decoration: InputDecoration(labelText: l10n.blockKindLabel),
            items: <DropdownMenuItem<ScheduleBlockKind>>[
              for (final kind in ScheduleBlockKind.values)
                DropdownMenuItem<ScheduleBlockKind>(
                  value: kind,
                  child: Text(kind.name),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _kind = value);
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickStart,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_format(_start)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickEnd,
                  icon: const Icon(Icons.stop),
                  label: Text(_format(_end)),
                ),
              ),
            ],
          ),
          if (_kind == ScheduleBlockKind.task) ...<Widget>[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _taskId,
              decoration: InputDecoration(labelText: l10n.blockTaskLabel),
              items: <DropdownMenuItem<String>>[
                for (final task in widget.tasks)
                  DropdownMenuItem<String>(
                    value: task.id,
                    child: Text(task.title),
                  ),
              ],
              onChanged: (value) => setState(() => _taskId = value),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.blockLocked),
            value: _locked,
            onChanged: (value) => setState(() => _locked = value),
          ),
          if (_error != null) Text(_error!),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.commonSave),
          ),
        ],
      ),
    );
  }

  String _format(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
