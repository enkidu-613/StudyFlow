import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/ai/ai_repository.dart';
import 'package:studyflow/util/uuid.dart';
import 'package:studyflow_domain/domain.dart';

final class AiWorkspaceChangeResult {
  const AiWorkspaceChangeResult({required this.draft, this.error});

  final AiWorkspaceChangeDraft draft;
  final Object? error;
  bool get succeeded => error == null;
}

/// Applies only user-confirmed drafts through the normal local repositories.
final class AiWorkspaceChangeService {
  const AiWorkspaceChangeService({required StudyFlowWorkspace workspace})
      : _workspace = workspace;

  final StudyFlowWorkspace _workspace;

  Future<List<AiWorkspaceChangeResult>> apply(
    Iterable<AiWorkspaceChangeDraft> drafts,
  ) async {
    final results = <AiWorkspaceChangeResult>[];
    for (final draft in drafts) {
      try {
        await _apply(draft);
        results.add(AiWorkspaceChangeResult(draft: draft));
      } on Object catch (error) {
        results.add(AiWorkspaceChangeResult(draft: draft, error: error));
      }
    }
    return results;
  }

  Future<void> _apply(AiWorkspaceChangeDraft draft) async {
    if (draft.entityType == AiWorkspaceEntityType.task) {
      await _applyTask(draft);
    } else {
      await _applySchedule(draft);
    }
  }

  Future<void> _applyTask(AiWorkspaceChangeDraft draft) async {
    if (draft.action == AiWorkspaceChangeAction.delete) {
      await _workspace.tasks
          .delete(draft.id!, write: await _workspace.nextWrite());
      return;
    }
    final old = draft.action == AiWorkspaceChangeAction.update
        ? await _requiredTask(draft.id!)
        : null;
    final values = draft.values;
    final task = Task(
      id: old?.id ?? newUuidV4(),
      title: _string(values, 'title', fallback: old?.title),
      description:
          _string(values, 'description', fallback: old?.description ?? ''),
      estimatedMinutes: _int(values, 'estimatedMinutes',
          fallback: old?.estimatedMinutes ?? 25),
      priority: _enum(TaskPriority.values, values, 'priority',
          old?.priority ?? TaskPriority.normal),
      status: _enum(
          TaskStatus.values, values, 'status', old?.status ?? TaskStatus.todo),
      tags: (values['tags'] as List?)?.whereType<String>() ??
          old?.tags ??
          const <String>[],
      repeatRule: _enum(RepeatRule.values, values, 'repeatRule',
          old?.repeatRule ?? RepeatRule.none),
    );
    await _workspace.tasks.save(task, write: await _workspace.nextWrite());
  }

  Future<void> _applySchedule(AiWorkspaceChangeDraft draft) async {
    if (draft.action == AiWorkspaceChangeAction.delete) {
      await _workspace.schedule
          .delete(draft.id!, write: await _workspace.nextWrite());
      return;
    }
    final old = draft.action == AiWorkspaceChangeAction.update
        ? await _requiredBlock(draft.id!)
        : null;
    final values = draft.values;
    final block = ScheduleBlock(
      id: old?.id ?? newUuidV4(),
      start: _date(values, 'start', fallback: old?.start),
      end: _date(values, 'end', fallback: old?.end),
      kind: _enum(ScheduleBlockKind.values, values, 'kind',
          old?.kind ?? ScheduleBlockKind.task),
      taskId: values.containsKey('taskId')
          ? values['taskId'] as String?
          : old?.taskId,
      source: old?.source ?? ScheduleBlockSource.manual,
      isLocked: values['isLocked'] as bool? ?? old?.isLocked ?? false,
      repeatRule: _enum(ScheduleRepeatRule.values, values, 'repeatRule',
          old?.repeatRule ?? ScheduleRepeatRule.none),
    );
    await _workspace.schedule.save(block, write: await _workspace.nextWrite());
  }

  Future<Task> _requiredTask(String id) async =>
      await _workspace.tasks.get(id) ?? (throw StateError('找不到要修改的任务。'));
  Future<ScheduleBlock> _requiredBlock(String id) async =>
      await _workspace.schedule.get(id) ?? (throw StateError('找不到要修改的日程。'));

  String _string(Map<String, Object?> values, String key, {String? fallback}) {
    final value = values[key] ?? fallback;
    if (value is! String || value.trim().isEmpty) {
      throw StateError('$key 必须是非空文本。');
    }
    return value.trim();
  }

  int _int(Map<String, Object?> values, String key, {required int fallback}) =>
      values[key] is int ? values[key]! as int : fallback;
  DateTime _date(Map<String, Object?> values, String key,
      {DateTime? fallback}) {
    final value = values[key];
    if (value is String && DateTime.tryParse(value) != null) {
      return DateTime.parse(value);
    }
    if (fallback != null) return fallback;
    throw StateError('$key 必须是本地 ISO 时间。');
  }

  T _enum<T extends Enum>(
      List<T> values, Map<String, Object?> source, String key, T fallback) {
    final value = source[key];
    return value is String ? values.byName(value) : fallback;
  }
}
