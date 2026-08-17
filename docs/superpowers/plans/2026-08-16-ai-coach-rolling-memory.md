# AI 教练滚动上下文记忆 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 AI 教练在每个账户的本机安全存储中保留长期对话摘要和最近 40 条原始消息，并在后续对话中连续使用它们。

**Architecture:** `AiCoachMemoryStore` 从“消息数组”升级为包含 `summary` 与 `messages` 的账户隔离快照，兼容已有数组格式。页面在原始消息超过 40 条时，将最早的一批与已有摘要交给用户配置的模型压缩；当前请求携带摘要、最近消息与实时工具数据，日程和任务仍由只读工具查询，不写入摘要。

**Tech Stack:** Flutter/Dart、`flutter_secure_storage`、OpenAI 兼容 Chat Completions、Flutter widget/unit tests。

## Global Constraints

- AI API Key、AI 对话和摘要只保存在当前设备的系统安全存储；不得写入 StudyFlow 服务端、Git、日志或截图。
- 记忆按 `workspace.accountId` 隔离；不同账户不得读取彼此的记录。
- 最近 40 条原始消息是模型的短期上下文；摘要只保存长期目标、偏好、承诺、未完成事项和重要事实。
- 任务、日程和当前时间继续经现有只读工具获取，摘要不得成为事实来源。
- 使用用户在“设置 → AI”中填写的同一 Base URL、模型和 API Key；本功能不增加 `.env` 变量或服务端配置。
- 当前工作树已有用户和既有代理的未提交改动；只改下列文件，不提交或清理无关文件。

---

### Task 1: 定义可迁移的对话记忆快照

**Files:**
- Modify: `apps/client/lib/features/ai/ai_coach_memory.dart`
- Test: `apps/client/test/features/ai/ai_coach_memory_test.dart`

**Consumes:** `AiCoachMessage.toJson()` 与 `AiCoachMessage.fromJson()`。

**Produces:** `AiCoachMemory(summary, messages)`；`AiCoachMemoryStore.load()` 和 `save()` 读写该快照。

- [ ] **Step 1: Write the failing tests**

```dart
test('loads the legacy message-list format with an empty summary', () async {
  final memory = await store.load(accountId: accountId);
  expect(memory.summary, isEmpty);
  expect(memory.messages, hasLength(2));
});

test('stores the rolling summary and messages for only one account', () async {
  await store.save(accountId: accountId, memory: memory);
  expect((await store.load(accountId: accountId)).summary, '长期目标');
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run from `apps/client` as the local Mac user:

```bash
mise exec -- flutter test test/features/ai/ai_coach_memory_test.dart
```

Expected: compile failure because `AiCoachMemory` and the snapshot API do not yet exist.

- [ ] **Step 3: Write the minimal storage migration**

```dart
final class AiCoachMemory {
  const AiCoachMemory({required this.summary, required this.messages});
  final String summary;
  final List<AiCoachMessage> messages;
}
```

Encode new snapshots as `{"summary": "...", "messages": [...]}`. When the stored JSON is the old list format, return the list with `summary: ''`; malformed content is deleted and becomes an empty snapshot.

- [ ] **Step 4: Run the test to verify it passes**

```bash
mise exec -- flutter test test/features/ai/ai_coach_memory_test.dart
```

Expected: all memory migration and account-isolation tests pass.

### Task 2: 生成并传递滚动摘要

**Files:**
- Modify: `apps/client/lib/features/ai/ai_repository.dart`
- Modify: `apps/client/lib/features/ai/today_ai_planning.dart`
- Test: `apps/client/test/features/ai/ai_repository_test.dart`
- Test: `apps/client/test/features/ai/today_ai_planning_test.dart`

**Consumes:** `AiCoachMemory.summary`、当前 AI 设置、原始对话消息。

**Produces:** `AiRepository.summarizeCoachMemory()`；`requestCoachReply()` 接收可选的 `conversationSummary` 并作为独立系统上下文发送。

- [ ] **Step 1: Write the failing tests**

```dart
test('puts the saved summary into the coach request before recent messages', () async {
  await repository.requestCoachReply(conversationSummary: '长期目标：十月前完成项目', ...);
  expect(firstRequestMessages, contains(summaryContextMessage));
});

test('uses a constrained Chinese prompt to summarize old messages', () async {
  final summary = await repository.summarizeCoachMemory(...);
  expect(summary, '长期目标：十月前完成项目。');
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `apps/client` as the local Mac user:

```bash
mise exec -- flutter test test/features/ai/ai_repository_test.dart test/features/ai/today_ai_planning_test.dart
```

Expected: missing summary parameter and summarizer method errors.

- [ ] **Step 3: Implement bounded summary calls**

Add one request without tools that asks for concise simplified-Chinese factual memory, caps output tokens, and says not to include medical claims or unverified schedule facts. Preserve existing provider error mapping. The coach request adds the summary only when non-empty and labels it as historical context rather than user instruction.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
mise exec -- flutter test test/features/ai/ai_repository_test.dart test/features/ai/today_ai_planning_test.dart
```

Expected: summaries and ordinary tool-call conversations both pass.

### Task 3: 页面滚动、保存与恢复

**Files:**
- Modify: `apps/client/lib/features/ai/recommendation_screen.dart`
- Modify: `apps/client/lib/main.dart`
- Modify: `apps/client/test/features/ai/recommendation_screen_test.dart`

**Consumes:** `AiCoachMemoryStore` snapshot API and a summarization callback supplied by the app route.

**Produces:** UI state with `summary` plus at most 40 messages; overflow compaction before the next coach reply.

- [ ] **Step 1: Write the failing widget tests**

```dart
testWidgets('compacts older messages and retains the latest forty', (tester) async {
  // Seed 41 messages, send once, and assert the summarizer received old text.
  // Assert saved memory has a summary and exactly 40 messages.
});

testWidgets('restores summary-backed history for the same account', (tester) async {
  // Seed a snapshot and verify the loaded request receives its summary.
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run from `apps/client` as the local Mac user:

```bash
mise exec -- flutter test test/features/ai/recommendation_screen_test.dart
```

Expected: callback and snapshot API are missing.

- [ ] **Step 3: Implement the rolling policy**

When a new message would exceed 40 entries, select the oldest 12–16 entries, ask the summarizer to merge them with the existing summary, remove exactly the compacted entries, then send the updated summary and remaining recent messages. Save after the user message, after a received assistant reply, and after compaction. If compaction fails, keep the original messages and show a local-memory error instead of discarding text.

- [ ] **Step 4: Run the test to verify it passes**

```bash
mise exec -- flutter test test/features/ai/recommendation_screen_test.dart
```

Expected: restored memory, overflow compaction, and standard chat interactions pass.

### Task 4: Full verification

**Files:**
- Verify only; no new deployment files or environment variables.

- [ ] **Step 1: Run format, static analysis, and all client tests**

Run from `apps/client` as the local Mac user:

```bash
mise exec -- dart format lib/features/ai test/features/ai
mise exec -- flutter analyze
mise exec -- flutter test
```

Expected: formatter makes no unexpected changes, analyzer reports no issues, and all tests pass.

- [ ] **Step 2: Verify manually on the local Mac client**

Run from `apps/client` as the local Mac user:

```bash
mise exec -- flutter run -d macos
```

Expected: after more than 40 alternating messages, the AI continues to recall the stored long-term goal while recent details remain intact. No VPS command, tunnel, `.env` change, or secret is required.

## Configuration and deployment impact

| Item | Change | Source | Sensitive | Verification |
|---|---|---|---|---|
| AI Base URL | No change; existing client setting is reused | 设置 → AI | 通常否 | AI 设置“连接测试”成功 |
| AI model | No change; existing client setting is reused | 设置 → AI | 否 | AI 回复与摘要均为中文 |
| AI API Key | No change; existing device-secure value is reused | 设置 → AI | 是 | 不显示在日志、Git 或 UI 中 |
| VPS / `.env` | No change | 不适用 | 不适用 | 无需部署服务端 |

## Safety and rollback

- 本功能不改服务器、数据库结构、容器、域名或 `.env`，不需要 VPS 操作。
- 回滚代码即可恢复为仅保存原始消息；已保存的新快照可由兼容读取逻辑安全打开。
- 若用户想清空长期记忆，应后续提供“清除 AI 对话记忆”入口；本次不自动删除任何既有对话。
