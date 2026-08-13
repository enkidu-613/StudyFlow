import 'package:flutter/material.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/l10n/l10n_extension.dart';
import 'package:studyflow/util/uuid.dart';
import 'package:studyflow_domain/domain.dart';

final class ScheduleBlockEditor extends StatefulWidget {
  const ScheduleBlockEditor({
    required this.workspace,
    required this.tasks,
    this.block,
    super.key,
  });

  final StudyFlowWorkspace workspace;
  final List<Task> tasks;
  final ScheduleBlock? block;

  @override
  State<ScheduleBlockEditor> createState() => _ScheduleBlockEditorState();
}

final class _ScheduleBlockEditorState extends State<ScheduleBlockEditor> {
  late ScheduleBlockKind _kind;
  late DateTime _start;
  late DateTime _end;
  String? _taskId;
  late bool _locked;
  String? _error;

  @override
  void initState() {
    super.initState();
    final block = widget.block;
    _kind = block?.kind ?? ScheduleBlockKind.task;
    _start = block?.start.toLocal() ?? DateTime.now();
    _end = block?.end.toLocal() ?? DateTime.now().add(const Duration(hours: 1));
    _taskId = block?.taskId;
    _locked = block?.isLocked ?? false;
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
    final existing = widget.block;
    final block = ScheduleBlock(
      id: existing?.id ?? newUuidV4(),
      start: _start,
      end: _end,
      kind: _kind,
      taskId: _kind == ScheduleBlockKind.task ? _taskId : null,
      source: existing?.source ?? ScheduleBlockSource.manual,
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
          Text(
            widget.block == null ? l10n.blockNew : l10n.blockEdit,
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ScheduleBlockKind>(
            initialValue: _kind,
            decoration: InputDecoration(labelText: l10n.blockKindLabel),
            items: <DropdownMenuItem<ScheduleBlockKind>>[
              for (final kind in ScheduleBlockKind.values)
                DropdownMenuItem<ScheduleBlockKind>(
                  value: kind,
                  child: Text(_kindLabel(context, kind)),
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

  String _kindLabel(BuildContext context, ScheduleBlockKind kind) =>
      switch (kind) {
        ScheduleBlockKind.task => context.l10n.blockKindTask,
        ScheduleBlockKind.rest => context.l10n.blockKindRest,
        ScheduleBlockKind.sleep => context.l10n.blockKindSleep,
        ScheduleBlockKind.breakTime => context.l10n.blockKindBreakTime,
      };

  String _format(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
