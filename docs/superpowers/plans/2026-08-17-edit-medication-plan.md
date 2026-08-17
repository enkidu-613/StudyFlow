# Edit Medication Plan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让用户点击已有药物计划后预填编辑表单，并以同一计划 ID 保存更新。

**Architecture:** `MedicationScreen` 将已选计划传给现有底部表单；表单以可选 `MedicationPlan` 初始化控制器，保存时保留 `id` 与 `createdAt`、更新 `updatedAt`。仓储现有 upsert 语义和同步实体不变。

**Tech Stack:** Flutter/Dart、现有 `MedicationPlan`、`MedicationRepository`、Flutter widget tests。

## Global Constraints

- 不增加环境变量、数据库表、迁移、网络请求或密钥。
- 不改变已记录的服药剂次；编辑仅覆盖药物计划记录。
- 用药文本仍由用户按医嘱填写，界面不解释或推断剂量。

---

### Task 1: Pre-filled editing and same-id save

**Files:**
- Modify: `apps/client/lib/features/medications/medication_screen.dart`
- Modify: `apps/client/test/app/studyflow_app_test.dart`

**Interfaces:**
- `_MedicationPlanEditor({MedicationPlan? plan})` displays `编辑药物计划` when `plan != null`.
- `MedicationScreen._openPlanEditor([MedicationPlan? plan])` saves the returned plan through `MedicationRepository.savePlan`.

- [ ] **Step 1: Write the failing widget test**

Create a plan in the testing workspace, tap its title in the `药物` route, update the dose field, save, then assert there is one plan with the original id and the new dose.

- [ ] **Step 2: Run the focused test to verify RED**

```bash
cd apps/client && mise exec -- flutter test test/app/studyflow_app_test.dart
```

Expected: the plan tile has no tap handler, so the prefilled form cannot open.

- [ ] **Step 3: Implement the minimal editor reuse**

Pass an optional plan into the bottom sheet, initialize its controllers from the plan, and build an updated `MedicationPlan` with `id: plan.id`, `createdAt: plan.createdAt`, `updatedAt: DateTime.now()`. Add an `onTap` to each plan tile.

- [ ] **Step 4: Run focused and full client verification**

```bash
cd apps/client && mise exec -- flutter test test/app/studyflow_app_test.dart
mise exec -- flutter analyze
mise exec -- flutter test
```

Expected: editing is proven, static analysis is clean, and all Flutter tests pass.

- [ ] **Step 5: Verify patch hygiene**

```bash
cd ../.. && git diff --check
```

Expected: no whitespace errors. Do not stage or commit unrelated existing modifications.
