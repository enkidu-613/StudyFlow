# Schedule Completion Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在每个日程实例结束时记录用户确认的执行结果和未完成原因，并把账户隔离的事实反馈交给 AI 顾问改善建议。

**Architecture:** 新建独立的 `ScheduleFeedback`，引用日程和某次发生时间，不改写 `ScheduleBlock` 模板。前台结束事件展示 Flutter 对话框；后台发送结束提醒，恢复前台后扫描近 48 小时未确认实例。反馈沿用 Drift 离线库、同步操作队列和服务端按账户保存，AI 只能读限量历史。

**Tech Stack:** Flutter/Dart、Drift/SQLite、FastAPI、SQLAlchemy、Alembic、PostgreSQL、OpenAI-compatible tools、Flutter tests、pytest。

## Global Constraints

- 不改变邮箱注册、登录和会话；反馈始终由当前 `accountId` 隔离。
- 不新增环境变量、密钥或第三方配置；AI Key 仍由客户端设置页管理。
- `notCompleted` 必须有非空原因；`completed` 可没有原因。
- 重复日程的每次发生各有一条反馈，提交反馈不改变模板或后续实例。
- AI 工具只读，最大返回 30 条，不能写任务、日程或反馈。
- 前台在结束时弹窗；后台只提醒，恢复时补问近 48 小时未确认实例。
- 客户端 schema 1 无损升级到 2；服务端 Alembic 006 无损升级到 007。
- 不写入真实 IP、密码、token、API Key 或恢复密钥。

---

## File Structure

- `packages/domain/lib/src/schedule_feedback.dart`: 反馈对象、验证、JSON。
- `packages/domain/lib/src/schedule_block.dart`: 按时间范围生成重复实例。
- `apps/client/lib/storage/{tables.dart,app_database.dart}`: 反馈表与 schema 迁移。
- `apps/client/lib/features/schedule/schedule_feedback_repository.dart`: 存取和同步入队。
- `apps/client/lib/features/schedule/schedule_completion_service.dart`: 结束事件和待确认扫描。
- `apps/client/lib/features/schedule/schedule_completion_dialog.dart`: 中文确认/原因对话框。
- `apps/client/lib/features/schedule/schedule_alarm_service.dart`: 开始提醒与结束事件编排。
- `apps/client/lib/features/shell/studyflow_shell.dart`: 事件订阅、对话框队列和保存。
- `apps/client/lib/features/ai/{ai_repository.dart,today_ai_planning.dart}`: 只读反馈工具。
- `server/app/{sync/schemas.py,db/models.py}`、`server/migrations/versions/007_schedule_feedback_entity.py`: 新同步实体和迁移。

## Task 1: Define the domain contract

**Files:**
- Create: `packages/domain/lib/src/schedule_feedback.dart`
- Modify: `packages/domain/lib/domain.dart`, `packages/domain/lib/src/schedule_block.dart`
- Test: `packages/domain/test/schedule_feedback_test.dart`, `packages/domain/test/schedule_block_test.dart`

**Interfaces:**
- `enum ScheduleFeedbackOutcome { completed, notCompleted }`
- `ScheduleFeedback({required String id, required String scheduleBlockId, required DateTime occurrenceStart, required DateTime occurrenceEnd, required ScheduleBlockKind kind, required ScheduleFeedbackOutcome outcome, String? reason, required DateTime confirmedAt})`
- `ScheduleBlock.occurrencesOverlapping(DateTime from, DateTime until, {int limit = 60})`

- [ ] **Step 1: Write failing tests**

```dart
test('unfinished feedback requires a reason', () {
  expect(() => ScheduleFeedback(
    id: feedbackId, scheduleBlockId: blockId,
    occurrenceStart: start, occurrenceEnd: end,
    kind: ScheduleBlockKind.task,
    outcome: ScheduleFeedbackOutcome.notCompleted,
    confirmedAt: end,
  ), throwsArgumentError);
});
```

- [ ] **Step 2: Verify RED**

```bash
mise exec -- dart test packages/domain/test/schedule_feedback_test.dart packages/domain/test/schedule_block_test.dart
```

Expected: failure because the types are absent.

- [ ] **Step 3: Implement the minimum**

Store timestamps as UTC. Reject `occurrenceEnd <= occurrenceStart`, and blank `reason` when the outcome is `notCompleted`. JSON uses `id`, `scheduleBlockId`, `occurrenceStart`, `occurrenceEnd`, `kind`, `outcome`, optional `reason`, `confirmedAt`. Overlap generation uses `end.difference(start)` and includes an in-progress repeating instance.

- [ ] **Step 4: Verify GREEN**

```bash
mise exec -- dart test packages/domain/test/schedule_feedback_test.dart packages/domain/test/schedule_block_test.dart
```

Expected: PASS.

## Task 2: Persist feedback locally and queue sync

**Files:**
- Modify: `apps/client/lib/storage/tables.dart`, `apps/client/lib/storage/app_database.dart`, generated `apps/client/lib/storage/app_database.g.dart`, `apps/client/lib/app/studyflow_workspace.dart`
- Create: `apps/client/lib/features/schedule/schedule_feedback_repository.dart`
- Test: `apps/client/test/features/schedule/schedule_feedback_repository_test.dart`, `apps/client/test/storage/app_database_migration_test.dart`

**Interfaces:**
- `ScheduleFeedbackRepository.save(ScheduleFeedback feedback, {required Write write, DateTime? updatedAt})`
- `get`, `list({int? limit})`, `findForOccurrence({required String scheduleBlockId, required DateTime occurrenceEnd})`
- `StudyFlowWorkspace.scheduleFeedback`

- [ ] **Step 1: Write failing tests**

```dart
test('saving feedback queues schedule_feedback', () async {
  await repository.save(feedback, write: await workspace.nextWrite());
  expect((await workspace.store.operations.pending(10)).single.entityType,
      EntityType.scheduleFeedback.wireName);
});
```

- [ ] **Step 2: Verify RED**

```bash
cd apps/client && mise exec -- flutter test test/features/schedule/schedule_feedback_repository_test.dart test/storage/app_database_migration_test.dart
```

Expected: compile failure because the entity and repository are absent.

- [ ] **Step 3: Implement storage and migration**

Add `_ScheduleFeedbacks` using the existing five-column payload-table pattern and compound key. Register it, set `schemaVersion => 2`, and `onUpgrade` creates only this table for `from < 2`. Add `EntityType.scheduleFeedback('schedule_feedback', 'schedule_feedbacks')`. Repository mirrors `FocusRepository`, verifies payload ID, compares UTC occurrence end, and sorts by newest confirmation.

- [ ] **Step 4: Regenerate and verify GREEN**

```bash
cd apps/client && mise exec -- dart run build_runner build --delete-conflicting-outputs
```

```bash
cd apps/client && mise exec -- flutter test test/features/schedule/schedule_feedback_repository_test.dart test/storage/app_database_migration_test.dart
```

Expected: tests PASS and existing v1 task records remain readable.

## Task 3: Sync `schedule_feedback` end-to-end

**Files:**
- Modify: `apps/client/lib/sync/sync_engine.dart`, `apps/client/test/sync/sync_engine_test.dart`
- Modify: `server/app/sync/schemas.py`, `server/app/db/models.py`
- Create: `server/migrations/versions/007_schedule_feedback_entity.py`
- Modify: `server/tests/test_sync_schemas.py`, `server/tests/test_plaintext_sync.py`, `server/tests/test_db_schema.py`

**Interfaces:** accepts `schedule_feedback` in Pydantic, database constraints and client pull validation.

- [ ] **Step 1: Write failing tests**

```dart
test('pulled feedback is stored for the active account', () async {
  api.pulledOperations = <SyncOperationV2>[await fixture.contractOperation(
    entityType: 'schedule_feedback', recordId: feedback.id,
    payload: feedback.toJson(),
  )];
  await fixture.engine.runOnce();
  expect((await fixture.scheduleFeedbackRepository.get(feedback.id))!.outcome,
      ScheduleFeedbackOutcome.notCompleted);
});
```

```python
async def test_push_accepts_schedule_feedback(sync_harness: SyncHarness) -> None:
    response = await sync_harness.push(
        sync_harness.first_access_token or "",
        make_operation(entity_type="schedule_feedback", payload=feedback_payload()),
    )
    assert response.status_code == 200
```

- [ ] **Step 2: Verify RED**

```bash
cd apps/client && mise exec -- flutter test test/sync/sync_engine_test.dart
```

```bash
cd server && mise exec -- poetry run pytest tests/test_sync_schemas.py tests/test_plaintext_sync.py tests/test_db_schema.py -q
```

Expected: the new entity is rejected.

- [ ] **Step 3: Implement validation and migration**

Add `schedule_feedback` to Python `EntityType`, both SQLAlchemy check constraints and client pull validation. Alembic 007 drops/recreates the named check constraints for `user_sync_operations` and legacy `sync_operations`, adding only this value. Client validates `ScheduleFeedback.fromJson`; it uses ordinary last-write-wins behavior, not schedule-template conflict cloning.

- [ ] **Step 4: Verify GREEN and migration round-trip**

```bash
cd apps/client && mise exec -- flutter test test/sync/sync_engine_test.dart
```

```bash
cd server && mise exec -- poetry run pytest tests/test_sync_schemas.py tests/test_plaintext_sync.py tests/test_db_schema.py -q
```

```bash
cd server && mise exec -- poetry run alembic upgrade head && mise exec -- poetry run alembic downgrade -1 && mise exec -- poetry run alembic upgrade head
```

Expected: tests PASS; reversible migration does not delete rows.

## Task 4: Confirm completion at end time

**Files:**
- Create: `apps/client/lib/features/schedule/schedule_completion_service.dart`, `apps/client/lib/features/schedule/schedule_completion_dialog.dart`
- Modify: `apps/client/lib/features/schedule/schedule_alarm_service.dart`, `apps/client/lib/features/shell/studyflow_shell.dart`, `apps/client/lib/features/schedule/schedule_block_editor.dart`
- Test: `apps/client/test/features/schedule/schedule_completion_service_test.dart`, `apps/client/test/features/schedule/schedule_completion_dialog_test.dart`, `apps/client/test/features/schedule/schedule_alarm_service_test.dart`

**Interfaces:**
- `ScheduleCompletionEvent(block, occurrenceStart, occurrenceEnd)`
- `ScheduleCompletionService.events` and `pendingSince(DateTime since, {DateTime? now})`
- `showScheduleCompletionDialog(BuildContext context, ScheduleCompletionEvent event)`

- [ ] **Step 1: Write failing tests**

```dart
testWidgets('unfinished task requires Chinese reason before submission', (tester) async {
  await tester.pumpWidget(dialogHarness(taskEvent));
  await tester.tap(find.text('未完成'));
  await tester.tap(find.text('提交'));
  expect(find.text('请填写未完成的原因'), findsOneWidget);
});
```

- [ ] **Step 2: Verify RED**

```bash
cd apps/client && mise exec -- flutter test test/features/schedule/schedule_completion_service_test.dart test/features/schedule/schedule_completion_dialog_test.dart test/features/schedule/schedule_alarm_service_test.dart
```

Expected: missing service/dialog fails.

- [ ] **Step 3: Implement the runtime flow**

Keep start alarms. Add an end reminder identifier `"${block.id}:end:${occurrenceStart.millisecondsSinceEpoch}"` and make its timer emit a service event without retaining UI context. Shell queues events so dialogs never overlap; on submit it saves a new UUID feedback using `workspace.nextWrite()`. Exact questions:

```dart
task: '这项学习/任务按计划完成了吗？'
rest: '这段休息按计划结束了吗？'
sleep: '这次睡眠按计划完成了吗？'
breakTime: '这段间歇按计划结束了吗？'
```

Negative result opens multiline input and rejects blanks with `请填写未完成的原因`. On lifecycle `resumed`, scan the previous 48 hours and ask one pending instance at a time. Editor deletes/rearms both start and end native reminders on save/delete.

- [ ] **Step 4: Verify GREEN**

```bash
cd apps/client && mise exec -- flutter test test/features/schedule/schedule_completion_service_test.dart test/features/schedule/schedule_completion_dialog_test.dart test/features/schedule/schedule_alarm_service_test.dart
```

Expected: timer, validation, duplicate prevention and cancellation tests PASS.

## Task 5: Add bounded feedback access for AI coach

**Files:**
- Modify: `apps/client/lib/features/ai/ai_repository.dart`, `apps/client/lib/features/ai/today_ai_planning.dart`
- Test: `apps/client/test/features/ai/ai_repository_test.dart`, `apps/client/test/features/ai/today_ai_planning_test.dart`

**Interfaces:**
- `typedef AiScheduleFeedbackLookup = Future<List<Map<String, Object?>>> Function(Map<String, Object?> arguments)`
- `requestCoachReply(..., required AiScheduleFeedbackLookup feedbackLookup)`
- Tool `get_schedule_feedback(limit: 1..30, after?: ISO-8601)`

- [ ] **Step 1: Write failing tool test**

```dart
test('coach feedback tool caps history at 30 records', () async {
  await repository.requestCoachReply(
    settings: settings, userMessage: '帮我分析', history: const [],
    taskTitles: const [], scheduleMetrics: const {},
    focusCompletionMetrics: const {}, sleepAggregates: const {},
    scheduleLookup: (_) async => const [],
    feedbackLookup: (args) async {
      expect(args['limit'], 30);
      return <Map<String, Object?>>[feedback.toJson()];
    },
  );
});
```

- [ ] **Step 2: Verify RED**

```bash
cd apps/client && mise exec -- flutter test test/features/ai/ai_repository_test.dart test/features/ai/today_ai_planning_test.dart
```

Expected: interface/tool absent.

- [ ] **Step 3: Implement read-only context**

Declare the Chinese read-only tool. Validate `limit` and `after`, throw `AiSchemaFailure` for invalid values, and cap to 30. Return only kind, outcome, reason, occurrence times and confirmation time. Initial context gains `feedbackCount`, `completedCount`, `notCompletedCount`. Prompt tells AI to reply in Chinese, distinguish fact from advice, and not diagnose the user.

- [ ] **Step 4: Verify GREEN**

```bash
cd apps/client && mise exec -- flutter test test/features/ai/ai_repository_test.dart test/features/ai/today_ai_planning_test.dart
```

Expected: bounded tool and context tests PASS.

## Task 6: Full verification and handoff

- [ ] **Step 1: Verify Flutter**

```bash
cd apps/client && mise exec -- flutter analyze && mise exec -- flutter test
```

Expected: exit status 0.

- [ ] **Step 2: Verify Python and migration**

```bash
cd server && mise exec -- poetry run pytest -q && mise exec -- poetry run alembic upgrade head
```

Expected: pytest passes and revision 007 is applied.

- [ ] **Step 3: Manually verify macOS**

```bash
cd apps/client && mise exec -- flutter run -d macos
```

Create a short rest block ending in two minutes, submit an unfinished reason, then ask the AI coach about recent execution. Expected: one Chinese dialog, one feedback operation, and a factual AI response with no automatic edits.

- [ ] **Step 4: Check patch hygiene**

```bash
git diff --check
```

```bash
git status --short
```

Expected: no whitespace errors; preserve unrelated changes. Do not commit unless the user requests it; if requested, stage exact feature files only.

## Self-review

- Tasks 1–3 make a per-occurrence account-synced entity; Task 4 collects all schedule kinds at end time; Task 5 gives the AI bounded factual context; Task 6 verifies all layers.
- The feature adds no secrets or user configuration requirements.
- Migrations are additive/reversible and AI never receives write authority.
