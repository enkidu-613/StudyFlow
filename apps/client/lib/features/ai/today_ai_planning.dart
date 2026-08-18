import 'package:studyflow/features/ai/ai_repository.dart';
import 'package:studyflow/features/ai/ai_settings_model.dart';
import 'package:studyflow_domain/domain.dart';

/// Converts locally stored study data into the bounded input for one AI draft.
final class TodayAiPlanning {
  TodayAiPlanning({
    required AiRepository repository,
    required AiSettingsStore settingsStore,
  })  : _repository = repository,
        _settingsStore = settingsStore;

  final AiRepository _repository;
  final AiSettingsStore _settingsStore;

  Future<AiCoachReply> requestCoachReply({
    required String userMessage,
    required List<AiCoachMessage> history,
    String conversationSummary = '',
    required List<Task> tasks,
    required List<ScheduleBlock> scheduleBlocks,
    required List<FocusSession> focusSessions,
    required List<CheckIn> checkIns,
    List<ScheduleFeedback> scheduleFeedback = const <ScheduleFeedback>[],
    List<MedicationPlan> medicationPlans = const <MedicationPlan>[],
  }) async {
    final settings = await _configuredSettings();
    final context = _context(
      tasks: tasks,
      scheduleBlocks: scheduleBlocks,
      focusSessions: focusSessions,
      checkIns: checkIns,
    );
    return _repository.requestCoachReply(
      settings: settings,
      userMessage: userMessage,
      history: history,
      conversationSummary: conversationSummary,
      taskTitles: context.taskTitles,
      scheduleMetrics: context.scheduleMetrics,
      focusCompletionMetrics: context.focusCompletionMetrics,
      sleepAggregates: context.sleepAggregates,
      scheduleLookup: (arguments) async => _scheduleBlocksForTool(
        arguments: arguments,
        scheduleBlocks: scheduleBlocks,
        tasks: tasks,
      ),
      feedbackLookup: (arguments) async => _feedbackForTool(
        arguments: arguments,
        feedback: scheduleFeedback,
      ),
      medicationLookup: (arguments) async => _medicationPlansForTool(
        arguments: arguments,
        medicationPlans: medicationPlans,
      ),
      taskLookup: (arguments) async => _tasksForTool(
        arguments: arguments,
        tasks: tasks,
      ),
      workspaceChangeLookup: (drafts) async => _withHumanReadablePreviews(
        drafts: drafts,
        tasks: tasks,
        scheduleBlocks: scheduleBlocks,
      ),
    );
  }

  Future<String> summarizeCoachMemory({
    required String existingSummary,
    required List<AiCoachMessage> messages,
  }) async =>
      _repository.summarizeCoachMemory(
        settings: await _configuredSettings(),
        existingSummary: existingSummary,
        messages: messages,
      );

  List<Map<String, Object?>> _scheduleBlocksForTool({
    required Map<String, Object?> arguments,
    required List<ScheduleBlock> scheduleBlocks,
    required List<Task> tasks,
  }) {
    final start = _toolDate(arguments['start']);
    final end = _toolDate(arguments['end']);
    final ids = arguments['blockIds'] is List
        ? (arguments['blockIds'] as List).whereType<String>().toSet()
        : const <String>{};
    final taskTitles = <String, String>{
      for (final task in tasks) task.id: task.title
    };
    return scheduleBlocks
        .where((block) =>
            (ids.isEmpty || ids.contains(block.id)) &&
            (start == null || !block.end.isBefore(start)) &&
            (end == null || !block.start.isAfter(end)))
        .take(20)
        .map((block) => <String, Object?>{
              'id': block.id,
              'start': block.start.toLocal().toIso8601String(),
              'end': block.end.toLocal().toIso8601String(),
              'kind': block.kind.name,
              'isLocked': block.isLocked,
              'repeatRule': block.repeatRule.name,
              'taskTitle':
                  block.taskId == null ? null : taskTitles[block.taskId],
            })
        .toList(growable: false);
  }

  DateTime? _toolDate(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  List<Map<String, Object?>> _tasksForTool({
    required Map<String, Object?> arguments,
    required List<Task> tasks,
  }) {
    final ids = arguments['taskIds'] is List
        ? (arguments['taskIds'] as List).whereType<String>().toSet()
        : const <String>{};
    final includeCompleted = arguments['includeCompleted'] as bool? ?? false;
    return tasks
        .where((task) =>
            (ids.isEmpty || ids.contains(task.id)) &&
            (includeCompleted ||
                (task.status != TaskStatus.completed &&
                    task.status != TaskStatus.cancelled)))
        .take(20)
        .map((task) => <String, Object?>{
              'id': task.id,
              'title': task.title,
              'description': task.description,
              'estimatedMinutes': task.estimatedMinutes,
              'priority': task.priority.name,
              'status': task.status.name,
              'tags': task.tags.toList(growable: false),
              'repeatRule': task.repeatRule.name,
            })
        .toList(growable: false);
  }

  List<AiWorkspaceChangeDraft> _withHumanReadablePreviews({
    required List<AiWorkspaceChangeDraft> drafts,
    required List<Task> tasks,
    required List<ScheduleBlock> scheduleBlocks,
  }) {
    final tasksById = <String, Task>{for (final task in tasks) task.id: task};
    final blocksById = <String, ScheduleBlock>{
      for (final block in scheduleBlocks) block.id: block,
    };
    return drafts.map((draft) {
      final values = draft.values;
      if (draft.entityType == AiWorkspaceEntityType.task) {
        final existing = draft.id == null ? null : tasksById[draft.id];
        return AiWorkspaceChangeDraft(
          entityType: draft.entityType,
          action: draft.action,
          id: draft.id,
          values: values,
          previewTitle: values['title'] as String? ?? existing?.title ?? '任务',
          previewPrevious: existing?.title,
        );
      }

      final existing = draft.id == null ? null : blocksById[draft.id];
      final taskId = values.containsKey('taskId')
          ? values['taskId'] as String?
          : existing?.taskId;
      final kindName = values['kind'] as String? ?? existing?.kind.name;
      final kind = _scheduleKindFromName(kindName);
      final start = _localDate(values['start']) ?? existing?.start.toLocal();
      final end = _localDate(values['end']) ?? existing?.end.toLocal();
      final previousTitle = existing == null
          ? null
          : tasksById[existing.taskId]?.title ??
              _scheduleKindLabel(existing.kind);
      return AiWorkspaceChangeDraft(
        entityType: draft.entityType,
        action: draft.action,
        id: draft.id,
        values: values,
        previewTitle: tasksById[taskId]?.title ?? _scheduleKindLabel(kind),
        previewTimeRange: _timeRange(start, end),
        previewPrevious: existing == null
            ? null
            : '$previousTitle（${_timeRange(existing.start.toLocal(), existing.end.toLocal()) ?? ''}）',
      );
    }).toList(growable: false);
  }

  DateTime? _localDate(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  String _scheduleKindLabel(ScheduleBlockKind kind) => switch (kind) {
        ScheduleBlockKind.sleep => '睡眠',
        ScheduleBlockKind.rest => '休息',
        ScheduleBlockKind.breakTime => '短休息',
        ScheduleBlockKind.task => '学习',
      };

  ScheduleBlockKind _scheduleKindFromName(String? name) {
    for (final kind in ScheduleBlockKind.values) {
      if (kind.name == name) return kind;
    }
    return ScheduleBlockKind.task;
  }

  String? _timeRange(DateTime? start, DateTime? end) {
    if (start == null && end == null) return null;
    String format(DateTime value) =>
        '${value.year}年${value.month}月${value.day}日 ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    if (start != null &&
        end != null &&
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day) {
      return '${format(start)}–${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    }
    return [if (start != null) format(start), if (end != null) format(end)]
        .join(' 至 ');
  }

  List<Map<String, Object?>> _feedbackForTool({
    required Map<String, Object?> arguments,
    required List<ScheduleFeedback> feedback,
  }) {
    final after = _toolDate(arguments['after']);
    final limit = (arguments['limit'] as int? ?? 20).clamp(1, 30);
    return feedback
        .where((item) => after == null || item.confirmedAt.isAfter(after))
        .take(limit)
        .map((item) => <String, Object?>{
              'kind': item.kind.name,
              'outcome': item.outcome.name,
              'reason': item.reason,
              'occurrenceStart': item.occurrenceStart.toIso8601String(),
              'occurrenceEnd': item.occurrenceEnd.toIso8601String(),
              'confirmedAt': item.confirmedAt.toIso8601String(),
            })
        .toList(growable: false);
  }

  List<Map<String, Object?>> _medicationPlansForTool({
    required Map<String, Object?> arguments,
    required List<MedicationPlan> medicationPlans,
  }) {
    final enabledOnly = arguments['enabledOnly'] as bool? ?? false;
    return medicationPlans
        .where((plan) => !enabledOnly || plan.enabled)
        .take(20)
        .map((plan) => <String, Object?>{
              'id': plan.id,
              'name': plan.name,
              'strength': plan.strength,
              'dose': plan.dose,
              'frequency': plan.frequency.name,
              'intervalDays': plan.intervalDays,
              'reminderTimes': plan.reminderTimes
                  .map((time) => <String, int>{
                        'hour': time.hour,
                        'minute': time.minute,
                      })
                  .toList(growable: false),
              'weekdays': plan.weekdays.toList()..sort(),
              'startDate': plan.startDate.toIso8601String(),
              'endDate': plan.endDate?.toIso8601String(),
              'enabled': plan.enabled,
              'note': plan.note,
            })
        .toList(growable: false);
  }

  Future<AiRecommendation> request({
    required List<Task> tasks,
    required List<ScheduleBlock> scheduleBlocks,
    required List<FocusSession> focusSessions,
    required List<CheckIn> checkIns,
  }) async {
    final settings = await _configuredSettings();
    final context = _context(
      tasks: tasks,
      scheduleBlocks: scheduleBlocks,
      focusSessions: focusSessions,
      checkIns: checkIns,
    );
    return _repository.requestRecommendation(
      settings: settings,
      taskTitles: context.taskTitles,
      scheduleMetrics: context.scheduleMetrics,
      focusCompletionMetrics: context.focusCompletionMetrics,
      sleepAggregates: context.sleepAggregates,
    );
  }

  Future<AiSettings> _configuredSettings() async {
    final settings = await _settingsStore.read();
    if (!settings.enabled || !settings.isConfigured) {
      throw StateError(
        '请先在设置中启用 AI 并填写 Base URL、模型和 API Key。',
      );
    }
    return settings;
  }

  _AiStudyContext _context({
    required List<Task> tasks,
    required List<ScheduleBlock> scheduleBlocks,
    required List<FocusSession> focusSessions,
    required List<CheckIn> checkIns,
  }) {
    final latestCheckIn = checkIns.isEmpty ? null : checkIns.first;
    return _AiStudyContext(
      taskTitles: tasks
          .where(
            (task) =>
                task.status != TaskStatus.completed &&
                task.status != TaskStatus.cancelled,
          )
          .map((task) => task.title)
          .take(20)
          .toList(growable: false),
      scheduleMetrics: <String, double>{
        'blockCount': scheduleBlocks.length.toDouble(),
        'lockedBlockCount':
            scheduleBlocks.where((block) => block.isLocked).length.toDouble(),
      },
      focusCompletionMetrics: <String, double>{
        'sessionCount': focusSessions.length.toDouble(),
        'finishedSessionCount': focusSessions
            .where((session) => session.isFinished)
            .length
            .toDouble(),
      },
      sleepAggregates: latestCheckIn == null
          ? const <String, double>{}
          : <String, double>{
              'sleepMinutes': latestCheckIn.sleepMinutes.toDouble(),
              'sleepQuality': latestCheckIn.sleepQuality.toDouble(),
              'energy': latestCheckIn.energy.toDouble(),
              'mood': latestCheckIn.mood.toDouble(),
            },
    );
  }
}

final class _AiStudyContext {
  const _AiStudyContext({
    required this.taskTitles,
    required this.scheduleMetrics,
    required this.focusCompletionMetrics,
    required this.sleepAggregates,
  });

  final List<String> taskTitles;
  final Map<String, double> scheduleMetrics;
  final Map<String, double> focusCompletionMetrics;
  final Map<String, double> sleepAggregates;
}
