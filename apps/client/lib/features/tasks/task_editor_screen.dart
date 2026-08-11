import 'package:flutter/material.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/util/uuid.dart';
import 'package:studyflow_domain/domain.dart';

final class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({required this.workspace, this.task, super.key});

  final StudyFlowWorkspace workspace;
  final Task? task;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

final class _TaskEditorScreenState extends State<TaskEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _minutesController;
  late final TextEditingController _tagsController;
  late TaskPriority _priority;
  late RepeatRule _repeatRule;
  String? _error;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _descriptionController =
        TextEditingController(text: task?.description ?? '');
    _minutesController =
        TextEditingController(text: task?.estimatedMinutes.toString() ?? '25');
    _tagsController = TextEditingController(text: task?.tags.join(', ') ?? '');
    _priority = task?.priority ?? TaskPriority.normal;
    _repeatRule = task?.repeatRule ?? RepeatRule.none;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _minutesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final estimatedMinutes = int.tryParse(_minutesController.text.trim());
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (estimatedMinutes == null || estimatedMinutes <= 0) {
      setState(() => _error = 'Minutes must be positive.');
      return;
    }
    final tags = _tagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    final task = Task(
      id: widget.task?.id ?? newUuidV4(),
      title: title,
      description: _descriptionController.text.trim(),
      estimatedMinutes: estimatedMinutes,
      priority: _priority,
      status: widget.task?.status ?? TaskStatus.todo,
      tags: tags,
      repeatRule: _repeatRule,
    );
    await widget.workspace.tasks.save(
      task,
      write: await widget.workspace.nextWrite(),
    );
    if (mounted) {
      Navigator.of(context).pop(task);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task == null ? 'New task' : 'Edit task'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            key: const Key('task-title-field'),
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('task-minutes-field'),
            controller: _minutesController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Estimated minutes',
              suffixText: 'min',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<TaskPriority>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'Priority'),
            items: <DropdownMenuItem<TaskPriority>>[
              for (final priority in TaskPriority.values)
                DropdownMenuItem<TaskPriority>(
                  value: priority,
                  child: Text(priority.name),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _priority = value);
              }
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<RepeatRule>(
            initialValue: _repeatRule,
            decoration: const InputDecoration(labelText: 'Repeat'),
            items: <DropdownMenuItem<RepeatRule>>[
              for (final rule in RepeatRule.values)
                DropdownMenuItem<RepeatRule>(
                  value: rule,
                  child: Text(rule.name),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _repeatRule = value);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tagsController,
            decoration: const InputDecoration(
              labelText: 'Tags',
              hintText: 'math, reading',
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('save-task-button'),
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
