# Schedule History Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将过去日程实例移出当前日程列表，提供可按日期查询、显示执行反馈的独立历史页面。

**Architecture:** 当前页按“是否仍有未来或进行中实例”过滤模板日程；历史页从模板展开过去实例并以 `scheduleBlockId + occurrenceEnd` 关联独立反馈记录。历史只读，不改变日程、反馈、同步或 AI 数据。

**Tech Stack:** Flutter/Dart、现有 ScheduleRepository、ScheduleFeedbackRepository、GoRouter、Flutter widget tests。

## Global Constraints

- 历史查询按设备本地日期分组和筛选，持久化时间仍为 UTC。
- 重复模板在当前页保留未来实例，在历史页展示每个已结束实例。
- 未确认反馈显示为“未确认”；未完成反馈显示原因。
- 不新增环境变量、数据库迁移、密钥、网络请求或自动写操作。
- 不删除既有日程/反馈；模板被删除后不虚构无法推导的历史行。

---

### Task 1: Extract current and history instance projection

**Files:**
- Create: `apps/client/lib/features/schedule/schedule_history.dart`
- Test: `apps/client/test/features/schedule/schedule_history_test.dart`

**Interfaces:**
- Produces `ScheduleHistoryEntry(block, occurrenceStart, occurrenceEnd, feedback)`.
- Produces `currentBlocks(List<ScheduleBlock> blocks, DateTime now)` and `historyEntries({required List<ScheduleBlock> blocks, required List<ScheduleFeedback> feedback, required DateTime from, required DateTime until})`.

- [ ] **Step 1: Write the failing projection test**

```dart
test('past one-off blocks are omitted from current while daily future instances remain', () {
  expect(currentBlocks(<ScheduleBlock>[past, future, daily], now), <ScheduleBlock>[future, daily]);
});
```

- [ ] **Step 2: Verify RED**

```bash
cd apps/client && mise exec -- flutter test test/features/schedule/schedule_history_test.dart
```

Expected: missing projection module fails compilation.

- [ ] **Step 3: Implement deterministic projection**

`currentBlocks` retains a non-repeating block when `end > now`, and a repeating block when its next generated occurrence starts before the configured future horizon. `historyEntries` expands only occurrences ending before `until`, uses `occurrencesOverlapping`, matches feedback with `'$blockId@${occurrenceEnd.microsecondsSinceEpoch}'`, and sorts newest end first.

- [ ] **Step 4: Verify GREEN**

```bash
cd apps/client && mise exec -- flutter test test/features/schedule/schedule_history_test.dart
```

Expected: current/history separation and feedback matching pass.

### Task 2: Build the date-filterable history route

**Files:**
- Create: `apps/client/lib/features/schedule/schedule_history_screen.dart`
- Modify: `apps/client/lib/features/schedule/schedule_screen.dart`
- Modify: `apps/client/lib/main.dart`
- Test: `apps/client/test/features/schedule/schedule_history_screen_test.dart`
- Modify: `apps/client/test/features/schedule/schedule_screen_test.dart`

**Interfaces:**
- Produces route `/schedule/history` receiving `StudyFlowWorkspace`.
- Produces AppBar action key `schedule-history-action`.
- Produces date picker key `schedule-history-date-filter`.

- [ ] **Step 1: Write failing widget tests**

```dart
testWidgets('history action opens entries filtered by selected local date', (tester) async {
  await tester.tap(find.byKey(const Key('schedule-history-action')));
  await tester.tap(find.byKey(const Key('schedule-history-date-filter')));
  await tester.tap(find.text('17').last);
  expect(find.text('未完成'), findsOneWidget);
  expect(find.text('临时不舒服'), findsOneWidget);
});
```

- [ ] **Step 2: Verify RED**

```bash
cd apps/client && mise exec -- flutter test test/features/schedule/schedule_history_screen_test.dart test/features/schedule/schedule_screen_test.dart
```

Expected: route/action/screen absent.

- [ ] **Step 3: Implement UI and navigation**

Add an AppBar history icon to `ScheduleScreen`, filter its list through `currentBlocks`, and navigate with `context.push('/schedule/history')`. History screen loads schedule and feedback once, offers a Material date picker plus a clear-filter button, groups entries by local end date, and renders Chinese state chips: `已完成`、`未完成`、`未确认`.

- [ ] **Step 4: Verify GREEN and full client checks**

```bash
cd apps/client && mise exec -- flutter test test/features/schedule/schedule_history_screen_test.dart test/features/schedule/schedule_screen_test.dart
```

```bash
cd apps/client && mise exec -- flutter analyze && mise exec -- flutter test
```

Expected: focused tests, analyzer and full suite pass.

### Task 3: Patch hygiene

**Files:**
- Modify: `docs/superpowers/plans/2026-08-17-schedule-history-screen.md` only if verification requires correction.

- [ ] **Step 1: Verify diff**

```bash
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 2: Preserve worktree isolation**

```bash
git status --short
```

Expected: report exact feature files; do not commit or stage unrelated pre-existing changes without a user request.

## Self-review

- Task 1 covers data semantics and repeat instances; Task 2 covers current-page filtering, history navigation, date filtering, feedback display and empty states; Task 3 verifies integration safety.
- The plan contains no new configuration or deployment work because the feature is local and read-only.
