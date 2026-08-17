# Medication Interval Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让药物计划支持从开始日期起每 N 天服用一次，包括隔天服用。

**Architecture:** `MedicationPlan` 增加正整数 `intervalDays`，每日频率固定为 1，weekly 固定为 7；新增 `everyNDays` 频率按本地日期与开始日期的整天差取模展开。表单显示周期天数，编辑时预填，保存仍通过既有计划 upsert 与同步流程。

**Tech Stack:** Flutter/Dart、共享 domain package、Flutter widget tests。

## Global Constraints

- `intervalDays` 必须为正整数；N=2 表示隔天。
- 周期从药物计划的开始日期计算，已记录剂次不被重新写入或删除。
- 不增加环境变量、数据库迁移、密钥或医疗建议逻辑。

---

### Task 1: Model and occurrence expansion

**Files:**
- Modify: `packages/domain/lib/src/medication.dart`
- Modify: `packages/domain/test/medication_test.dart`

**Interfaces:**
- `MedicationFrequency.everyNDays`
- `MedicationPlan(intervalDays: int = 1)`

- [ ] **Step 1: Write a failing test**

Assert a plan with `frequency: MedicationFrequency.everyNDays`, `intervalDays: 2`, and start date 2026-08-17 produces only the 17th, 19th and 21st within a five-day query.

- [ ] **Step 2: Verify RED**

```bash
cd packages/domain && mise exec -- dart test test/medication_test.dart
```

Expected: `everyNDays` and `intervalDays` are undefined.

- [ ] **Step 3: Implement model validation, JSON and expansion**

Add `intervalDays` serialization with `fromJson` default 1 for prior saved daily plans. Reject values less than 1. In `occurrencesBetween`, compute `day.difference(startDate).inDays % intervalDays == 0` for `everyNDays`.

- [ ] **Step 4: Verify GREEN**

```bash
cd packages/domain && mise exec -- dart test test/medication_test.dart
```

Expected: interval expansion and existing domain tests pass.

### Task 2: Expose interval input in plan create/edit form

**Files:**
- Modify: `apps/client/lib/features/medications/medication_screen.dart`
- Modify: `apps/client/test/app/studyflow_app_test.dart`

- [ ] **Step 1: Write a failing widget test**

Create a plan with interval 2, open editing, assert the field reads `2`, change it to `3`, save, then assert the stored plan has `intervalDays == 3` and `frequency == MedicationFrequency.everyNDays`.

- [ ] **Step 2: Verify RED**

```bash
cd apps/client && mise exec -- flutter test test/app/studyflow_app_test.dart
```

Expected: no interval input exists and the plan cannot store interval 3.

- [ ] **Step 3: Implement the minimal form change**

Add a numeric `每隔几天服用（每日填 1，隔天填 2）` controller. Parse a positive integer; value 1 saves `daily`, values above 1 save `everyNDays`. Preserve it during edits.

- [ ] **Step 4: Verify full client checks**

```bash
cd apps/client && mise exec -- flutter analyze
mise exec -- flutter test
cd ../.. && git diff --check
```

Expected: static analysis and full suite pass without whitespace errors.
