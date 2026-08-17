# AI 日程任务操作、睡眠时段与 Markdown 对话 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 AI 教练以待确认草案形式管理日程和任务，睡眠打卡按起止时间记录，并以 Markdown 渲染 AI 回复。

**Architecture:** AI 工具只产生结构化 `AiWorkspaceChangeDraft`，由对话页呈现并通过路由注入的本地仓库回调应用。`CheckIn` 扩展可空 UTC 睡眠起止时间并保留分钟字段兼容旧数据。AI 气泡使用本地 Markdown renderer，用户消息仍为纯文本。

**Tech Stack:** Flutter/Dart、Drift、现有本地同步仓库、OpenAI-compatible tool calls、flutter_markdown。

## Global Constraints

- 所有 AI 写操作先显示待应用变更卡，绝不静默写入。
- 删除日程和任务必须显示原对象信息；不实现 AI 药物写入。
- 时间在 UI 和 AI 工具边界使用设备本地墙上时间，持久化使用 UTC。
- 保留 `sleepMinutes`，新字段必须兼容旧序列化记录。
- 不引入服务端密钥或新的环境变量。

---

### Task 1: 定义并验证 AI 工作区变更草案

**Files:**
- Modify: `apps/client/lib/features/ai/ai_repository.dart`
- Modify: `apps/client/test/features/ai/ai_repository_test.dart`

**Interfaces:**
- Produces: `AiWorkspaceChangeDraft`、`AiCoachReply.drafts`、`propose_workspace_changes` 工具。
- Consumes: 现有 `Task`、`ScheduleBlock` 字段和只读查询工具。

- [ ] 写失败测试：模型发出日程新建、任务更新和删除草案时，客户端返回验证后的草案但不写入。
- [ ] 运行 `mise exec -- flutter test test/features/ai/ai_repository_test.dart`，确认新测试失败。
- [ ] 实现严格的草案解析、每次最多 10 项、更新/删除必须含 ID、工具回调只校验并回传草案。
- [ ] 运行同一测试，确认通过。

### Task 2: 将草案应用到当前账号的本地仓库

**Files:**
- Create: `apps/client/lib/features/ai/ai_workspace_change_service.dart`
- Create: `apps/client/test/features/ai/ai_workspace_change_service_test.dart`
- Modify: `apps/client/lib/main.dart`

**Interfaces:**
- Consumes: `AiWorkspaceChangeDraft`、`StudyFlowWorkspace.nextWrite()`、任务和日程仓库。
- Produces: `AiWorkspaceChangeResult`，包含每项成功或可显示失败原因。

- [ ] 写失败测试：创建日程、更新任务、删除日程分别调用对应仓库并生成同步操作。
- [ ] 运行服务测试确认失败。
- [ ] 实现本地时间解析、UUID 创建、实体查找、写入、删除和逐项失败收集。
- [ ] 在 AI 路由注入该服务。
- [ ] 运行服务测试确认通过。

### Task 3: 在 AI 对话中显示并应用草案，以及 Markdown 回复

**Files:**
- Modify: `apps/client/pubspec.yaml`
- Modify: `apps/client/lib/features/ai/recommendation_screen.dart`
- Modify: `apps/client/test/features/ai/recommendation_screen_test.dart`

**Interfaces:**
- Consumes: `AiCoachReply.drafts` 与应用回调。
- Produces: 可勾选变更卡、“应用已选变更”按钮和 Markdown AI 气泡。

- [ ] 写失败 widget 测试：AI Markdown 回复渲染标题/列表，草案卡显示并可取消一项后应用。
- [ ] 运行 widget 测试确认失败。
- [ ] 加入 Markdown 依赖；按消息保存草案；渲染安全 Markdown；应用成功后更新卡片状态，失败保留错误。
- [ ] 运行 widget 测试确认通过。

### Task 4: 用睡眠起止时间替代手输分钟数

**Files:**
- Modify: `packages/domain/lib/src/check_in.dart`
- Modify: `packages/domain/test/check_in_test.dart`
- Modify: `apps/client/lib/storage/tables.dart`
- Modify: `apps/client/lib/storage/app_database.dart`
- Modify: `apps/client/lib/storage/app_database.g.dart`
- Modify: `apps/client/lib/features/checkins/check_in_repository.dart`
- Modify: `apps/client/lib/features/checkins/check_in_screen.dart`
- Modify: `apps/client/lib/features/home/home_screen.dart`
- Modify: `apps/client/test/features/checkins/check_in_screen_test.dart`

**Interfaces:**
- Produces: `CheckIn.sleepStartedAt`、`CheckIn.sleepEndedAt` 和从本地 TimeOfDay 计算新 CheckIn 的共享构造逻辑。
- Consumes: 旧 `sleepMinutes` 数据和现有 Drift 操作记录。

- [ ] 写失败领域测试：同日与跨午夜时间计算分钟数，并验证 JSON round-trip 与旧 JSON 兼容。
- [ ] 运行领域测试确认失败。
- [ ] 添加可空持久化字段和数据库版本迁移；实现自动时长计算与 1 分钟至 24 小时校验。
- [ ] 将两个打卡弹窗改为时间选择器和动态时长文本；历史与首页显示区间优先、分钟回退。
- [ ] 运行领域/打卡 widget 测试确认通过。

### Task 5: 全量验证

**Files:**
- Modify: 本计划的复选状态。

- [ ] 运行 `mise exec -- dart format` 处理改动的 Dart 文件。
- [ ] 运行 `mise exec -- flutter analyze`。
- [ ] 运行 `mise exec -- flutter test`。
- [ ] 运行 `git diff --check`。
