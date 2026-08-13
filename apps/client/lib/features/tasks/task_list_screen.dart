import 'package:flutter/material.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/tasks/task_editor_screen.dart';
import 'package:studyflow/l10n/app_localizations.dart';
import 'package:studyflow/l10n/l10n_extension.dart';
import 'package:studyflow/widgets/confirm_delete_dialog.dart';
import 'package:studyflow_domain/domain.dart';

enum _TaskFilter { all, todo, inProgress, completed }

final class TaskListScreen extends StatefulWidget {
  const TaskListScreen({required this.workspace, super.key});

  final StudyFlowWorkspace workspace;

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

final class _TaskListScreenState extends State<TaskListScreen> {
  List<Task> _tasks = <Task>[];
  Object? _error;
  bool _loading = true;
  _TaskFilter _filter = _TaskFilter.all;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final tasks = await widget.workspace.tasks.list();
      if (!mounted) {
        return;
      }
      setState(() {
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

  Future<void> _openEditor([Task? task]) async {
    final saved = await Navigator.of(context).push<Task>(
      MaterialPageRoute<Task>(
        builder: (context) => TaskEditorScreen(
          workspace: widget.workspace,
          task: task,
        ),
      ),
    );
    if (saved != null) {
      await _refresh();
    }
  }

  Future<void> _setStatus(Task task, TaskStatus status) async {
    if (task.status == status) {
      return;
    }
    await widget.workspace.tasks.save(
      _withStatus(task, status),
      write: await widget.workspace.nextWrite(),
    );
    await _refresh();
  }

  Future<void> _toggleComplete(Task task) async {
    final next = task.status == TaskStatus.completed
        ? TaskStatus.todo
        : TaskStatus.completed;
    await _setStatus(task, next);
  }

  Future<void> _deleteTask(Task task) async {
    final confirmed = await showDeleteConfirmationDialog(
      context,
      title: context.l10n.taskDelete,
      body: context.l10n.taskDeleteBody,
      confirmKey: 'task-delete-dialog',
    );
    if (!confirmed || !mounted) {
      return;
    }
    await widget.workspace.tasks.delete(
      task.id,
      write: await widget.workspace.nextWrite(),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.taskDeleted)));
    await _refresh();
  }

  Future<void> _showTaskActions(Task task) async {
    final l10n = context.l10n;
    final action = await showModalBottomSheet<_TaskAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              key: const Key('task-action-edit'),
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.taskEditAction),
              onTap: () =>
                  Navigator.of(context).pop(_TaskAction.edit),
            ),
            if (task.status != TaskStatus.inProgress)
              ListTile(
                key: const Key('task-action-in-progress'),
                leading: const Icon(Icons.play_circle_outline),
                title: Text(l10n.taskMarkInProgress),
                onTap: () =>
                    Navigator.of(context).pop(_TaskAction.inProgress),
              ),
            if (task.status != TaskStatus.completed)
              ListTile(
                key: const Key('task-action-complete'),
                leading: const Icon(Icons.check_circle_outline),
                title: Text(l10n.taskMarkCompleted),
                onTap: () => Navigator.of(context).pop(_TaskAction.complete),
              ),
            if (task.status != TaskStatus.cancelled)
              ListTile(
                key: const Key('task-action-cancel'),
                leading: const Icon(Icons.cancel_outlined),
                title: Text(l10n.taskMarkCancelled),
                onTap: () => Navigator.of(context).pop(_TaskAction.cancelled),
              ),
            const Divider(height: 1),
            ListTile(
              key: const Key('task-action-delete'),
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l10n.taskDelete,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              onTap: () => Navigator.of(context).pop(_TaskAction.delete),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case _TaskAction.edit:
        await _openEditor(task);
      case _TaskAction.inProgress:
        await _setStatus(task, TaskStatus.inProgress);
      case _TaskAction.complete:
        await _setStatus(task, TaskStatus.completed);
      case _TaskAction.cancelled:
        await _setStatus(task, TaskStatus.cancelled);
      case _TaskAction.delete:
        await _deleteTask(task);
    }
  }

  Task _withStatus(Task task, TaskStatus status) => Task(
        id: task.id,
        title: task.title,
        description: task.description,
        estimatedMinutes: task.estimatedMinutes,
        priority: task.priority,
        status: status,
        tags: task.tags,
        repeatRule: task.repeatRule,
      );

  List<Task> _filtered() {
    final tasks = _tasks
        .where((task) => task.status != TaskStatus.cancelled)
        .toList();
    return switch (_filter) {
      _TaskFilter.all => tasks,
      _TaskFilter.todo => tasks
          .where((task) =>
              task.status == TaskStatus.todo ||
              task.status == TaskStatus.scheduled)
          .toList(),
      _TaskFilter.inProgress => tasks
          .where((task) => task.status == TaskStatus.inProgress)
          .toList(),
      _TaskFilter.completed => tasks
          .where((task) => task.status == TaskStatus.completed)
          .toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navTasks)),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<_TaskFilter>(
              segments: <ButtonSegment<_TaskFilter>>[
                ButtonSegment<_TaskFilter>(
                  value: _TaskFilter.all,
                  label: Text(l10n.taskFilterAll),
                ),
                ButtonSegment<_TaskFilter>(
                  value: _TaskFilter.todo,
                  label: Text(l10n.taskFilterTodo),
                ),
                ButtonSegment<_TaskFilter>(
                  value: _TaskFilter.inProgress,
                  label: Text(l10n.taskFilterInProgress),
                ),
                ButtonSegment<_TaskFilter>(
                  value: _TaskFilter.completed,
                  label: Text(l10n.taskFilterCompleted),
                ),
              ],
              selected: <_TaskFilter>{_filter},
              onSelectionChanged: (selection) {
                setState(() => _filter = selection.first);
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildList(l10n),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: l10n.taskNew,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildList(AppLocalizations l10n) {
    final filtered = _filtered();
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
    if (_tasks.isEmpty) {
      return ListView(
        children: <Widget>[
          const SizedBox(height: 96),
          Icon(
            Icons.checklist_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Center(child: Text(l10n.tasksEmpty)),
          const SizedBox(height: 8),
          Center(
            child: Text(
              l10n.taskEmptyHint,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        ],
      );
    }
    if (filtered.isEmpty) {
      return ListView(
        children: <Widget>[
          const SizedBox(height: 96),
          Center(child: Text(l10n.taskEmptyFiltered)),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              key: const Key('task-filter-clear'),
              onPressed: () => setState(() => _filter = _TaskFilter.all),
              child: Text(l10n.taskFilterAll),
            ),
          ),
        ],
      );
    }

    final groups = <_TaskGroup, List<Task>>{
      _TaskGroup.inProgress: <Task>[],
      _TaskGroup.todo: <Task>[],
      _TaskGroup.completed: <Task>[],
    };
    for (final task in filtered) {
      final group = switch (task.status) {
        TaskStatus.inProgress => _TaskGroup.inProgress,
        TaskStatus.todo || TaskStatus.scheduled => _TaskGroup.todo,
        TaskStatus.completed => _TaskGroup.completed,
        TaskStatus.cancelled => _TaskGroup.completed,
      };
      groups[group]!.add(task);
    }
    for (final list in groups.values) {
      list.sort(_byPriorityThenTitle);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        if (groups[_TaskGroup.inProgress]!.isNotEmpty)
          _TaskGroupHeader(
            key: const Key('task-group-in-progress'),
            label: l10n.taskGroupInProgress(groups[_TaskGroup.inProgress]!.length),
          ),
        for (final task in groups[_TaskGroup.inProgress]!) _TaskTile(
          key: Key('task-list-item-${task.id}'),
          task: task,
          onToggle: () => _toggleComplete(task),
          onTap: () => _openEditor(task),
          onLongPress: () => _showTaskActions(task),
          onDelete: () => _deleteTask(task),
        ),
        if (groups[_TaskGroup.todo]!.isNotEmpty)
          _TaskGroupHeader(
            key: const Key('task-group-todo'),
            label: l10n.taskGroupTodo(groups[_TaskGroup.todo]!.length),
          ),
        for (final task in groups[_TaskGroup.todo]!) _TaskTile(
          key: Key('task-list-item-${task.id}'),
          task: task,
          onToggle: () => _toggleComplete(task),
          onTap: () => _openEditor(task),
          onLongPress: () => _showTaskActions(task),
          onDelete: () => _deleteTask(task),
        ),
        if (groups[_TaskGroup.completed]!.isNotEmpty)
          _TaskGroupHeader(
            key: const Key('task-group-completed'),
            label:
                l10n.taskGroupCompleted(groups[_TaskGroup.completed]!.length),
          ),
        for (final task in groups[_TaskGroup.completed]!) _TaskTile(
          key: Key('task-list-item-${task.id}'),
          task: task,
          onToggle: () => _toggleComplete(task),
          onTap: () => _openEditor(task),
          onLongPress: () => _showTaskActions(task),
          onDelete: () => _deleteTask(task),
        ),
      ],
    );
  }

  int _byPriorityThenTitle(Task left, Task right) {
    final byPriority = right.priority.index.compareTo(left.priority.index);
    if (byPriority != 0) {
      return byPriority;
    }
    return left.title.compareTo(right.title);
  }
}

enum _TaskAction { edit, inProgress, complete, cancelled, delete }

enum _TaskGroup { inProgress, todo, completed }

final class _TaskGroupHeader extends StatelessWidget {
  const _TaskGroupHeader({required this.label, super.key});

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

final class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.onToggle,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    super.key,
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final completed = task.status == TaskStatus.completed;
    return Dismissible(
      key: Key('task-dismiss-${task.id}'),
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
        leading: Checkbox(
          value: completed,
          onChanged: (_) => onToggle(),
        ),
        title: Text(
          task.title,
          style: completed
              ? TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                  decoration: TextDecoration.lineThrough,
                )
              : null,
        ),
        subtitle: Text(
          l10n.taskRowSubtitle(task.estimatedMinutes, task.priority.name),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}
