# Medication Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变既有日程语义的前提下，提供独立、可同步的药物计划与服药记录；将待服药实例显示到今天和日程中，并在到点时让用户记录已服、跳过或延后。用户可以粘贴医嘱，由其已配置的 AI 仅生成待确认草稿；原始医嘱永不进入同步数据、聊天记忆或服务器日志。

**Architecture:** 药物计划（`MedicationPlan`）和剂次记录（`MedicationDoseRecord`）是两类独立同步实体。客户端由计划按本地时区展开剂次，提醒服务只安排已确认计划的未来剂次；今天页、日程页只读显示这些剂次并跳转至服药确认。医嘱草稿存在客户端安全存储，只有用户逐项确认后才转换为同步计划。AI 不可改动药物计划，也不提供诊断、处方、加减量、漏服补服或相互作用建议。

**Tech Stack:** Flutter/Dart、Drift SQLite、FastAPI、SQLAlchemy/Alembic、PostgreSQL、现有同步协议、`flutter_secure_storage`、现有 OpenAI-compatible 客户端 AI 接口、Flutter/Domain/Pytest 测试。

## Global Constraints

- 药物功能是提醒与记录工具，不是医疗建议功能。固定安全提示覆盖误服、漏服、加量、不适、不良反应和相互作用提问：查看药盒/医嘱并联系医生或药师；紧急情况联系当地急救服务。
- 只允许用户确认后创建或修改药物计划；AI 提取的任何字段都必须在 UI 中可见、可改、逐项确认。模糊字段保持“待确认”，不能猜测时间、频次或剂量。
- 原始医嘱只保存至本机安全存储的短期草稿；不写入 `MedicationPlan`、`MedicationDoseRecord`、SQLite 同步操作、服务器 API payload、AI 聊天记忆、日志或分析。
- AI API 的 `baseUrl`、模型名和 API key 保持“客户端 → 设置 → AI 设置”来源；本功能不增加服务端 AI 密钥或 `.env` 变量。
- 服药计划不是普通 `ScheduleBlock`，日程 AI 工具不得读取、创建、移动、锁定或删除它。页面仅展示剂次卡片，避免被日程自动重排。
- 计划与记录按账户/工作区隔离；同步使用现有 LWW/revision 协议，删除为 tombstone。日期和时间以 UTC 持久化、以设备本地时区显示与展开。
- 本次不改变现有数据库密码、账户密码、JWT、Podman 服务或部署配置；本机调试不需要隧道。

---

### Task 1: Define validated medication domain entities and occurrence expansion

**Files:**
- Create: `packages/domain/lib/src/medication.dart`
- Modify: `packages/domain/lib/domain.dart`
- Test: `packages/domain/test/medication_test.dart`

**Interfaces:**
- `MedicationTime(hour, minute)` avoids Flutter UI types in the shared domain package.
- `MedicationPlan` contains confirmed name, strength text, dose text, `MedicationFrequency`, local times, weekly weekdays when applicable, start/end date, enabled flag, timestamps and revision metadata; it deliberately has no raw-order field.
- `MedicationDoseRecord` uses `MedicationDoseOutcome.taken|skipped|delayed`, planned UTC instant, recorded UTC instant, optional delayed-until instant and optional user note.
- `MedicationPlan.occurrencesBetween(from, until, localTimeZone)` deterministically expands daily or weekly planned instants.

- [ ] **Step 1: Write failing domain tests**

Cover daily expansion, weekly-day filtering, disabled/end-dated plans, serialization round trips, and invalid states (empty medication name/dose/times; weekly plan without weekdays; delayed record without a future time).

```bash
cd packages/domain && mise exec -- dart test test/medication_test.dart
```

Expected: compilation fails because `medication.dart` is absent.

- [ ] **Step 2: Implement minimal immutable domain models**

Implement `toJson`/`fromJson`, constructor invariants and deterministic occurrence generation. Preserve user-entered strength/dose as text rather than parsing or interpreting clinical units.

- [ ] **Step 3: Verify GREEN**

```bash
cd packages/domain && mise exec -- dart test test/medication_test.dart
```

Expected: all medication domain cases pass.

### Task 2: Add local persistence and account-scoped repositories

**Files:**
- Modify: `apps/client/lib/storage/tables.dart`
- Modify: `apps/client/lib/storage/app_database.dart`
- Modify: `apps/client/lib/storage/app_database.g.dart` (generated)
- Modify: `apps/client/lib/storage/operation_dao.dart`
- Create: `apps/client/lib/features/medications/medication_repository.dart`
- Modify: `apps/client/lib/app/studyflow_workspace.dart`
- Test: `apps/client/test/features/medications/medication_repository_test.dart`
- Test: `apps/client/test/storage/operation_dao_test.dart`

- [ ] **Step 1: Write failing repository tests**

Test that a plan and a dose record are stored only for the active account, writes enqueue the correct sync entity type, plan deletion is tombstoned, and raw-order strings cannot be passed to persisted models.

```bash
cd apps/client && mise exec -- flutter test test/features/medications/medication_repository_test.dart test/storage/operation_dao_test.dart
```

Expected: missing `MedicationRepository` / entity types fail compilation.

- [ ] **Step 2: Add schema v3 tables and repositories**

Create local tables for plans and dose records with account id, entity id, JSON payload, revision and deleted marker matching existing generic entity storage. Bump the Drift schema version and add a non-destructive migration. Expose plan/record streams and commands through `StudyFlowWorkspace`; never persist draft medical-order text in these tables.

- [ ] **Step 3: Verify GREEN**

```bash
cd apps/client && mise exec -- flutter test test/features/medications/medication_repository_test.dart test/storage/operation_dao_test.dart
```

Expected: account isolation, operation creation and persistence tests pass.

### Task 3: Extend server-side sync validation and PostgreSQL constraints

**Files:**
- Modify: `server/app/db/models.py`
- Modify: `server/app/sync/schemas.py`
- Create: `server/migrations/versions/008_medication_entities.py`
- Modify: `server/tests/test_sync_schemas.py`

- [ ] **Step 1: Write failing server schema tests**

Test that `medication_plan` and `medication_dose_record` are valid synced entity types, while an unknown type and a plan payload containing `rawMedicalOrder` are rejected.

```bash
cd server && mise exec -- poetry run pytest tests/test_sync_schemas.py -q
```

Expected: medication entity payload/type validation fails before implementation.

- [ ] **Step 2: Add explicit allowed entity types and database constraint migration**

Extend the Python Literal/schema and the `sync_operations` check constraint using Alembic revision `008`. Validation must reject raw-order keys recursively at the API boundary, including tombstone-safe payloads, so a client bug cannot leak medical orders into Postgres.

- [ ] **Step 3: Verify GREEN and migration chain**

```bash
cd server && mise exec -- poetry run pytest tests/test_sync_schemas.py -q
mise exec -- poetry run alembic upgrade head
```

Expected: schema tests pass and the local development database reaches revision `008` without data loss.

### Task 4: Implement secure one-time AI draft extraction

**Files:**
- Create: `apps/client/lib/features/medications/medication_draft.dart`
- Create: `apps/client/lib/features/medications/medication_draft_store.dart`
- Modify: `apps/client/lib/features/ai/ai_repository.dart`
- Test: `apps/client/test/features/medications/medication_draft_test.dart`
- Test: `apps/client/test/features/ai/ai_repository_test.dart`

- [ ] **Step 1: Write failing draft tests**

Test strict JSON parsing, uncertain field preservation, an extraction request that asks only for a structured draft, secure-store deletion after successful confirmation, and local safety-keyword interception that returns the fixed notice without calling the AI client.

```bash
cd apps/client && mise exec -- flutter test test/features/medications/medication_draft_test.dart test/features/ai/ai_repository_test.dart
```

Expected: draft model/store/extraction API are missing.

- [ ] **Step 2: Implement draft-only AI flow**

Add `MedicationDraft` and a secure-storage-backed `MedicationDraftStore`, scoped by account and draft id. Extend the AI repository with an explicit extraction method that sends a strict Chinese schema and does not append the medical order to coach memory. Parsing errors and missing required values produce an editable draft with `needsConfirmation`; they never create a plan. The local safety notice prevents interpretation of harmful/urgent medication scenarios.

- [ ] **Step 3: Verify GREEN**

```bash
cd apps/client && mise exec -- flutter test test/features/medications/medication_draft_test.dart test/features/ai/ai_repository_test.dart
```

Expected: no raw-order persistence, correct parsing and safety interception are proven.

### Task 5: Build medication plans, records and history UI

**Files:**
- Create: `apps/client/lib/features/medications/medication_screen.dart`
- Create: `apps/client/lib/features/medications/medication_plan_editor.dart`
- Create: `apps/client/lib/features/medications/medication_draft_review_screen.dart`
- Create: `apps/client/lib/features/medications/medication_dose_confirmation_dialog.dart`
- Create: `apps/client/lib/features/medications/medication_history_screen.dart`
- Modify: `apps/client/lib/features/home/home_screen.dart`
- Modify: `apps/client/lib/features/schedule/schedule_screen.dart`
- Modify: `apps/client/lib/features/shell/studyflow_shell.dart`
- Modify: `apps/client/lib/main.dart`
- Test: `apps/client/test/features/medications/medication_screen_test.dart`
- Test: `apps/client/test/features/medications/medication_dose_confirmation_dialog_test.dart`

- [ ] **Step 1: Write failing widget tests**

Test that the new `药物` destination shows today's due doses and plans; an AI draft shows every field as editable/confirmable; a plan cannot save before required confirmations; and the dose dialog records `已服`/`跳过`/`延后` with note and delayed time validation.

```bash
cd apps/client && mise exec -- flutter test test/features/medications/medication_screen_test.dart test/features/medications/medication_dose_confirmation_dialog_test.dart
```

Expected: destination, editor and confirmation dialog are absent.

- [ ] **Step 2: Implement user-facing workflows**

Add a sixth bottom navigation destination named `药物`, with sections for today, active plans and history. A manual plan form has clear text labels: 药品名称、规格、每次用量、提醒时间、开始/结束日期 and only confirmed values. The “粘贴医嘱生成草稿” route explains the AI boundary before sending. Today and Schedule show read-only medication dose cards; tapping opens the dose confirmation dialog, never the schedule editor. Dose history supports date filtering and contains outcome/time/note.

- [ ] **Step 3: Verify GREEN**

```bash
cd apps/client && mise exec -- flutter test test/features/medications/medication_screen_test.dart test/features/medications/medication_dose_confirmation_dialog_test.dart
```

Expected: important empty, draft, validation and outcome paths pass in Chinese UI.

### Task 6: Add reliable in-app and notification reminder scheduling

**Files:**
- Create: `apps/client/lib/features/medications/medication_reminder_service.dart`
- Modify: `apps/client/lib/app/studyflow_workspace.dart`
- Modify: `apps/client/lib/features/shell/studyflow_shell.dart`
- Test: `apps/client/test/features/medications/medication_reminder_service_test.dart`

- [ ] **Step 1: Write failing reminder service tests**

Test that only enabled confirmed future doses produce notifications, an already recorded dose is not prompted again, a delayed record schedules its next prompt at the user-selected time, and app-resume scans overdue doses into confirmation events.

```bash
cd apps/client && mise exec -- flutter test test/features/medications/medication_reminder_service_test.dart
```

Expected: medication reminder service/events are absent.

- [ ] **Step 2: Implement bounded reminder lifecycle**

Create a service parallel to the existing schedule alarm service. It schedules a bounded rolling horizon of native notifications, attaches opaque dose identifiers only, emits foreground confirmation events, and cancels/rebuilds notifications when plans or records change. `StudyFlowShell` observes lifecycle resume and queues overdue unrecorded dose dialogs. Background OS behavior remains a notification; direct notification action handling is not claimed unless the existing platform plugin supports it.

- [ ] **Step 3: Verify GREEN**

```bash
cd apps/client && mise exec -- flutter test test/features/medications/medication_reminder_service_test.dart
```

Expected: scheduling and resume reconciliation behavior pass without duplicate prompts.

### Task 7: End-to-end verification, local Podman check and handoff documentation

**Files:**
- Modify: `README.md` only if the existing local run instructions require a user-visible medication data note.
- Modify: `docs/superpowers/plans/2026-08-17-medication-reminders.md` only to record proven verification results.

- [ ] **Step 1: Run full checks**

```bash
cd packages/domain && mise exec -- dart test
cd apps/client && mise exec -- flutter analyze && mise exec -- flutter test
cd server && mise exec -- poetry run pytest -q
cd ../infra && podman compose --env-file .env ps
cd .. && git diff --check
```

Expected: domain, Flutter and server tests pass; local Podman services are either healthy or reported as an external environment condition; diff check has no whitespace errors.

- [ ] **Step 2: Perform non-secret manual smoke path**

At the local Mac client: create a manual non-clinical test plan, confirm a due dose, check it appears in medication history and sync operation queue, then delete the test plan. Do not paste an actual order, key, password or personal health data into test output.

- [ ] **Step 3: Document user-facing behavior and rollback**

State that no new `.env` configuration is needed. Identify the only optional configuration: `设置 → AI 设置` uses the user’s existing Base URL/model/API key. Explain safe rollback: disable a plan to stop future reminders; remove the feature deployment only after backing up the local Postgres volume; do not delete dose history casually.

## Self-review

- Task 1 makes clinical-looking strings non-interpreted domain data; Tasks 2–3 protect sync/account boundaries; Task 4 protects raw medical orders; Tasks 5–6 provide the visible user flow and reminders; Task 7 verifies the complete local slice.
- The plan deliberately does not add prescription intelligence, provider integration, dosage conversion, emergency triage, Supabase, a cloud tunnel, or a new secret.
