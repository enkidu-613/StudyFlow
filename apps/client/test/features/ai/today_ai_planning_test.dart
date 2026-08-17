import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/features/ai/ai_repository.dart';
import 'package:studyflow/features/ai/ai_settings_model.dart';
import 'package:studyflow/features/ai/today_ai_planning.dart';
import 'package:studyflow_domain/domain.dart';

void main() {
  test('sends a Chinese coaching message with prior conversation context',
      () async {
    final repository = _CapturingAiRepository();
    final planner = TodayAiPlanning(
      repository: repository,
      settingsStore: _ConfiguredSettingsStore(),
    );

    await planner.requestCoachReply(
      userMessage: '我昨晚几乎没睡，今天怎么安排学习？',
      history: <AiCoachMessage>[
        const AiCoachMessage.assistant('先告诉我你现在的精力。'),
      ],
      tasks: <Task>[_task('完成 Python 项目', TaskStatus.todo)],
      scheduleBlocks: const <ScheduleBlock>[],
      focusSessions: const <FocusSession>[],
      checkIns: const <CheckIn>[],
    );

    expect(repository.coachMessage, '我昨晚几乎没睡，今天怎么安排学习？');
    expect(repository.coachHistory.single.content, '先告诉我你现在的精力。');
    expect(repository.coachTaskTitles, <String>['完成 Python 项目']);
  });

  test('exposes only matching schedule details to the coach tool', () async {
    final repository = _CapturingAiRepository();
    final planner = TodayAiPlanning(
      repository: repository,
      settingsStore: _ConfiguredSettingsStore(),
    );
    final task = _task('完成 Python 项目', TaskStatus.todo);
    final selectedBlock = ScheduleBlock(
      id: '11111111-1111-4111-8111-111111111111',
      start: DateTime.utc(2026, 8, 16, 8),
      end: DateTime.utc(2026, 8, 16, 9),
      kind: ScheduleBlockKind.task,
      taskId: task.id,
      source: ScheduleBlockSource.manual,
      isLocked: true,
      repeatRule: ScheduleRepeatRule.weekly,
    );
    final otherBlock = ScheduleBlock(
      id: '22222222-2222-4222-8222-222222222222',
      start: DateTime.utc(2026, 8, 17, 8),
      end: DateTime.utc(2026, 8, 17, 9),
      kind: ScheduleBlockKind.breakTime,
      taskId: null,
      source: ScheduleBlockSource.manual,
      isLocked: false,
    );

    await planner.requestCoachReply(
      userMessage: '我今天上午有什么安排？',
      history: const <AiCoachMessage>[],
      tasks: <Task>[task],
      scheduleBlocks: <ScheduleBlock>[selectedBlock, otherBlock],
      focusSessions: const <FocusSession>[],
      checkIns: const <CheckIn>[],
    );

    final blocks = await repository.scheduleLookup!(<String, Object?>{
      'blockIds': <String>[selectedBlock.id],
    });

    expect(blocks, hasLength(1));
    expect(blocks.single, <String, Object?>{
      'id': selectedBlock.id,
      'start': selectedBlock.start.toLocal().toIso8601String(),
      'end': selectedBlock.end.toLocal().toIso8601String(),
      'kind': 'task',
      'isLocked': true,
      'repeatRule': 'weekly',
      'taskTitle': '完成 Python 项目',
    });
  });

  test('builds a today planning request from local study data', () async {
    final repository = _CapturingAiRepository();
    final planner = TodayAiPlanning(
      repository: repository,
      settingsStore: _ConfiguredSettingsStore(),
    );

    await planner.request(
      tasks: <Task>[
        _task('Active task', TaskStatus.todo),
        _task('Finished task', TaskStatus.completed),
      ],
      scheduleBlocks: <ScheduleBlock>[
        ScheduleBlock(
          id: '11111111-1111-4111-8111-111111111111',
          start: DateTime.utc(2026, 8, 16, 8),
          end: DateTime.utc(2026, 8, 16, 9),
          kind: ScheduleBlockKind.task,
          taskId: null,
          source: ScheduleBlockSource.manual,
          isLocked: true,
        ),
      ],
      focusSessions: <FocusSession>[
        FocusSession(
          id: '22222222-2222-4222-8222-222222222222',
          taskId: '33333333-3333-4333-8333-333333333333',
          startedAt: DateTime.utc(2026, 8, 16, 8),
          endedAt: DateTime.utc(2026, 8, 16, 8, 25),
          completionMethod: FocusCompletionMethod.timer,
        ),
      ],
      checkIns: <CheckIn>[
        CheckIn(
          id: '44444444-4444-4444-8444-444444444444',
          recordedAt: DateTime.utc(2026, 8, 16, 7),
          sleepMinutes: 420,
          sleepQuality: 4,
          energy: 3,
          mood: 5,
          feedback: 'Good sleep',
        ),
      ],
    );

    expect(repository.taskTitles, <String>['Active task']);
    expect(repository.scheduleMetrics, <String, double>{
      'blockCount': 1,
      'lockedBlockCount': 1,
    });
    expect(repository.focusMetrics, <String, double>{
      'sessionCount': 1,
      'finishedSessionCount': 1,
    });
    expect(repository.sleepMetrics, <String, double>{
      'sleepMinutes': 420,
      'sleepQuality': 4,
      'energy': 3,
      'mood': 5,
    });
  });

  test('exposes saved medication plans to the coach tool', () async {
    final repository = _CapturingAiRepository();
    final planner = TodayAiPlanning(
      repository: repository,
      settingsStore: _ConfiguredSettingsStore(),
    );
    final plan = MedicationPlan(
      id: '66666666-6666-4666-8666-666666666666',
      name: '示例药物',
      strength: '10 mg',
      dose: '每次 1 片',
      frequency: MedicationFrequency.everyNDays,
      intervalDays: 2,
      reminderTimes: const <MedicationTime>[
        MedicationTime(hour: 8, minute: 30),
      ],
      startDate: DateTime.utc(2026, 8, 16),
      enabled: true,
      createdAt: DateTime.utc(2026, 8, 16),
      updatedAt: DateTime.utc(2026, 8, 16),
      note: '随餐服用',
    );

    await planner.requestCoachReply(
      userMessage: '我的药怎么安排？',
      history: const <AiCoachMessage>[],
      tasks: const <Task>[],
      scheduleBlocks: const <ScheduleBlock>[],
      focusSessions: const <FocusSession>[],
      checkIns: const <CheckIn>[],
      medicationPlans: <MedicationPlan>[plan],
    );

    final plans = await repository.medicationLookup!(<String, Object?>{
      'enabledOnly': true,
    });
    expect(plans, hasLength(1));
    expect(plans.single['name'], '示例药物');
    expect(plans.single['frequency'], 'everyNDays');
    expect(plans.single['intervalDays'], 2);
    expect(plans.single['reminderTimes'], <Object?>[
      <String, int>{'hour': 8, 'minute': 30},
    ]);
  });

  test('adds a human-readable preview to a schedule change draft', () async {
    final repository = _CapturingAiRepository();
    final planner = TodayAiPlanning(
      repository: repository,
      settingsStore: _ConfiguredSettingsStore(),
    );
    final task = _task('完成 Python 项目', TaskStatus.todo);
    final block = ScheduleBlock(
      id: '11111111-1111-4111-8111-111111111111',
      start: DateTime.utc(2026, 8, 17, 2, 30),
      end: DateTime.utc(2026, 8, 17, 9, 45),
      kind: ScheduleBlockKind.task,
      taskId: task.id,
      source: ScheduleBlockSource.manual,
      isLocked: false,
    );

    await planner.requestCoachReply(
      userMessage: '请生成调整草案。',
      history: const <AiCoachMessage>[],
      tasks: <Task>[task],
      scheduleBlocks: <ScheduleBlock>[block],
      focusSessions: const <FocusSession>[],
      checkIns: const <CheckIn>[],
    );

    final drafts = await repository.workspaceChangeLookup!(
      <AiWorkspaceChangeDraft>[
        AiWorkspaceChangeDraft(
          entityType: AiWorkspaceEntityType.scheduleBlock,
          action: AiWorkspaceChangeAction.update,
          id: block.id,
          values: const <String, Object?>{'end': '2026-08-17T16:00:00'},
        ),
      ],
    );

    expect(drafts.single.previewTitle, '完成 Python 项目');
    expect(drafts.single.previewTimeRange, contains('2026年8月17日'));
    expect(drafts.single.previewTimeRange, contains('10:30–16:00'));
  });
}

Task _task(String title, TaskStatus status) => Task(
      id: '55555555-5555-4555-8555-555555555555',
      title: title,
      description: '',
      estimatedMinutes: 25,
      priority: TaskPriority.normal,
      status: status,
      tags: const <String>[],
      repeatRule: RepeatRule.none,
    );

final class _ConfiguredSettingsStore implements AiSettingsStore {
  @override
  Future<void> clear() async {}

  @override
  Future<AiSettings> read() async => const AiSettings(
        baseUrl: 'https://ai.example.com/v1',
        model: 'test-model',
        apiKey: 'test-key',
        enabled: true,
      );

  @override
  Future<void> write(AiSettings settings) async {}
}

final class _CapturingAiRepository implements AiRepository {
  String? coachMessage;
  List<AiCoachMessage> coachHistory = const <AiCoachMessage>[];
  List<String>? coachTaskTitles;
  List<String>? taskTitles;
  Map<String, double>? scheduleMetrics;
  Map<String, double>? focusMetrics;
  Map<String, double>? sleepMetrics;
  AiScheduleLookup? scheduleLookup;
  AiMedicationLookup? medicationLookup;
  AiWorkspaceChangeLookup? workspaceChangeLookup;

  @override
  Future<AiRecommendation> requestRecommendation({
    required AiSettings settings,
    required List<String> taskTitles,
    required Map<String, double> scheduleMetrics,
    required Map<String, double> focusCompletionMetrics,
    required Map<String, double> sleepAggregates,
  }) async {
    this.taskTitles = taskTitles;
    this.scheduleMetrics = scheduleMetrics;
    focusMetrics = focusCompletionMetrics;
    sleepMetrics = sleepAggregates;
    return AiRecommendation(
      summary: 'Plan ready',
      candidateChanges: const <CandidateScheduleChange>[],
      reasonCodes: const <String>[],
    );
  }

  @override
  Future<AiCoachReply> requestCoachReply({
    required AiSettings settings,
    required String userMessage,
    required List<AiCoachMessage> history,
    String conversationSummary = '',
    required List<String> taskTitles,
    required Map<String, double> scheduleMetrics,
    required Map<String, double> focusCompletionMetrics,
    required Map<String, double> sleepAggregates,
    required AiScheduleLookup scheduleLookup,
    AiScheduleFeedbackLookup? feedbackLookup,
    AiMedicationLookup? medicationLookup,
    AiWorkspaceChangeLookup? workspaceChangeLookup,
  }) async {
    coachMessage = userMessage;
    coachHistory = history;
    coachTaskTitles = taskTitles;
    this.scheduleLookup = scheduleLookup;
    this.medicationLookup = medicationLookup;
    this.workspaceChangeLookup = workspaceChangeLookup;
    return const AiCoachReply('好的，我们先安排休息。');
  }

  @override
  Future<String> summarizeCoachMemory({
    required AiSettings settings,
    required String existingSummary,
    required List<AiCoachMessage> messages,
  }) async =>
      existingSummary;

  @override
  Future<void> testConnection(AiSettings settings) async {}
}
