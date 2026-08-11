import 'dart:collection';

enum TaskPriority { low, normal, high, urgent }

enum TaskStatus { todo, scheduled, inProgress, completed, cancelled }

enum RepeatRule { none, daily, weekdays, weekly }

final class Task {
  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.estimatedMinutes,
    required this.priority,
    required this.status,
    required Iterable<String> tags,
    required this.repeatRule,
  }) : _tags = UnmodifiableListView<String>(List<String>.from(tags)) {
    if (estimatedMinutes <= 0) {
      throw ArgumentError.value(
        estimatedMinutes,
        'estimatedMinutes',
        'must be positive',
      );
    }
  }

  factory Task.fromJson(Map<String, Object?> json) => Task(
        id: json['id']! as String,
        title: json['title']! as String,
        description: json['description']! as String,
        estimatedMinutes: json['estimatedMinutes']! as int,
        priority: TaskPriority.values.byName(json['priority']! as String),
        status: TaskStatus.values.byName(json['status']! as String),
        tags: (json['tags']! as List<Object?>).cast<String>(),
        repeatRule: RepeatRule.values.byName(json['repeatRule']! as String),
      );

  final String id;
  final String title;
  final String description;
  final int estimatedMinutes;
  final TaskPriority priority;
  final TaskStatus status;
  final UnmodifiableListView<String> _tags;
  final RepeatRule repeatRule;

  List<String> get tags => _tags;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'description': description,
        'estimatedMinutes': estimatedMinutes,
        'priority': priority.name,
        'status': status.name,
        'tags': _tags,
        'repeatRule': repeatRule.name,
      };
}
