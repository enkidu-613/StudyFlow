import 'dart:async';

import 'package:flutter/material.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/schedule/schedule_block_editor.dart';
import 'package:studyflow/l10n/app_localizations.dart';
import 'package:studyflow/l10n/l10n_extension.dart';
import 'package:studyflow/widgets/confirm_delete_dialog.dart';
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

  Future<void> _openEditor([ScheduleBlock? block]) async {
    final saved = await showModalBottomSheet<ScheduleBlock>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ScheduleBlockEditor(
        workspace: widget.workspace,
        tasks: _tasks,
        block: block,
      ),
    );
    if (saved != null) {
      await _refresh();
    }
  }

  Future<void> _deleteBlock(ScheduleBlock block) async {
    if (block.isLocked) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.blockLockedHint)));
      return;
    }
    final confirmed = await showDeleteConfirmationDialog(
      context,
      title: context.l10n.blockDelete,
      body: context.l10n.blockDeleteBody,
      confirmKey: 'block-delete-dialog',
    );
    if (!confirmed || !mounted) {
      return;
    }
    await widget.workspace.schedule.delete(
      block.id,
      write: await widget.workspace.nextWrite(),
    );
    widget.workspace.alarms.cancel(block.id);
    unawaited(
      widget.workspace.platform.cancelReminder(block.id).then(
            (_) {},
            onError: (_) {},
          ),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.blockDeleted)));
    await _refresh();
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
            : _buildList(l10n),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: l10n.blockNew,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildList(AppLocalizations l10n) {
    if (_error != null) {
      return ListView(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text('$_error'),
          ),
        ],
      );
    }
    if (_blocks.isEmpty) {
      return ListView(
        children: <Widget>[
          const SizedBox(height: 96),
          Icon(
            Icons.event_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Center(child: Text(l10n.scheduleEmpty)),
          const SizedBox(height: 8),
          Center(
            child: Text(
              l10n.scheduleEmptyHint,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        ],
      );
    }

    final days = <DateTime, List<ScheduleBlock>>{};
    for (final block in _blocks) {
      final day = DateTime(
        block.start.toLocal().year,
        block.start.toLocal().month,
        block.start.toLocal().day,
      );
      days.putIfAbsent(day, () => <ScheduleBlock>[]).add(block);
    }
    final sortedDays = days.keys.toList()..sort();
    final today = DateTime.now();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        for (final day in sortedDays) ...<Widget>[
          _DayHeader(
            key: Key('schedule-day-${day.year}-${day.month}-${day.day}'),
            label: _dayLabel(l10n, day, today),
          ),
          for (final block in days[day]!)
            _BlockTile(
              key: Key('schedule-block-${block.id}'),
              block: block,
              taskTitle: _taskTitleFor(block),
              onTap: () => _openEditor(block),
              onLongPress: () => _showBlockActions(block),
              onDelete: () => _deleteBlock(block),
            ),
        ],
      ],
    );
  }

  Future<void> _showBlockActions(ScheduleBlock block) async {
    final l10n = context.l10n;
    final action = await showModalBottomSheet<_BlockAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              key: const Key('block-action-edit'),
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.blockEdit),
              onTap: () => Navigator.of(context).pop(_BlockAction.edit),
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('block-action-delete'),
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l10n.blockDelete,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              onTap: () => Navigator.of(context).pop(_BlockAction.delete),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case _BlockAction.edit:
        await _openEditor(block);
      case _BlockAction.delete:
        await _deleteBlock(block);
    }
  }

  String _taskTitleFor(ScheduleBlock block) {
    if (block.kind != ScheduleBlockKind.task || block.taskId == null) {
      return _kindLabel(context, block.kind);
    }
    return _tasks
            .where((task) => task.id == block.taskId)
            .map((task) => task.title)
            .firstOrNull ??
        context.l10n.blockUnknownTask;
  }

  String _kindLabel(BuildContext context, ScheduleBlockKind kind) =>
      switch (kind) {
        ScheduleBlockKind.task => context.l10n.blockKindTask,
        ScheduleBlockKind.rest => context.l10n.blockKindRest,
        ScheduleBlockKind.sleep => context.l10n.blockKindSleep,
        ScheduleBlockKind.breakTime => context.l10n.blockKindBreakTime,
      };

  String _dayLabel(
    AppLocalizations l10n,
    DateTime day,
    DateTime today,
  ) {
    final isToday = day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;
    if (isToday) {
      return l10n.scheduleGroupToday;
    }
    final tomorrow = today.add(const Duration(days: 1));
    final isTomorrow = day.year == tomorrow.year &&
        day.month == tomorrow.month &&
        day.day == tomorrow.day;
    if (isTomorrow) {
      return l10n.scheduleGroupTomorrow;
    }
    return '${day.month}/${day.day}';
  }
}

enum _BlockAction { edit, delete }

final class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

final class _BlockTile extends StatelessWidget {
  const _BlockTile({
    required this.block,
    required this.taskTitle,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    super.key,
  });

  final ScheduleBlock block;
  final String taskTitle;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('block-dismiss-${block.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.onError,
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: _KindIcon(kind: block.kind),
        title: Text(taskTitle),
        subtitle: Text(
          '${_formatTime(block.start)} - ${_formatTime(block.end)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (block.repeatRule != ScheduleRepeatRule.none) ...[
              Icon(
                Icons.repeat,
                size: 18,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(width: 4),
            ],
            if (block.isLocked)
              const Icon(Icons.lock_outline)
            else
              const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

final class _KindIcon extends StatelessWidget {
  const _KindIcon({required this.kind});

  final ScheduleBlockKind kind;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (kind) {
      ScheduleBlockKind.task => (Icons.school_outlined, Colors.indigo),
      ScheduleBlockKind.rest => (Icons.self_improvement, Colors.teal),
      ScheduleBlockKind.sleep => (Icons.bedtime_outlined, Colors.deepPurple),
      ScheduleBlockKind.breakTime => (Icons.coffee_outlined, Colors.brown),
    };
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.12),
      child: Icon(icon, size: 20, color: color),
    );
  }
}
