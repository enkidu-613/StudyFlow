import 'package:flutter/material.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/tasks/task_editor_screen.dart';
import 'package:studyflow_domain/domain.dart';

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

  Future<void> _toggleComplete(Task task) async {
    if (task.status == TaskStatus.completed) {
      return;
    }
    await widget.workspace.tasks.save(
      _withStatus(task, TaskStatus.completed),
      write: await widget.workspace.nextWrite(),
    );
    await _refresh();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
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
                  for (final task in _tasks)
                    ListTile(
                      leading: Checkbox(
                        value: task.status == TaskStatus.completed,
                        onChanged: (_) => _toggleComplete(task),
                      ),
                      title: Text(task.title),
                      subtitle: Text(
                        '${task.estimatedMinutes} min  ${task.priority.name}',
                      ),
                      trailing: Icon(
                        task.status == TaskStatus.completed
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                      ),
                      onTap: () => _openEditor(task),
                    ),
                  if (_tasks.isEmpty && _error == null)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No tasks')),
                    ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: 'New task',
        child: const Icon(Icons.add),
      ),
    );
  }
}
