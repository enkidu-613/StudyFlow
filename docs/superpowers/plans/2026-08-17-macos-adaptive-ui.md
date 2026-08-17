# StudyFlow macOS 自适应界面 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在保留 Android 移动端体验的前提下，为 macOS 宽窗口提供侧栏导航和受限内容宽度。

**Architecture:** 继续使用现有 Flutter 页面、GoRouter 和 `StudyFlowWorkspace`。只在 `StudyFlowShell` 根据父级宽度切换 `NavigationBar` 与桌面侧栏；页面内容通过共享容器限制最大宽度，不引入平台判断或第二套业务页面。

**Tech Stack:** Flutter/Dart、Material 3、LayoutBuilder、Flutter widget tests、现有 GoRouter。

## Global Constraints

- 使用 `LayoutBuilder` 的可用宽度，不检测设备型号或强制锁定窗口方向。
- `maxWidth < 900` 使用现有 `NavigationBar`；`maxWidth >= 900` 使用桌面侧栏。
- 不改变认证、同步、AI、日程、任务、药物数据和路由路径。
- 不覆盖工作区已有修改；本次只修改导航壳、相关测试和本计划涉及的文档。
- 每个行为先写失败测试，再写最小实现。

### Task 1: Add responsive shell tests

**Files:**
- Modify: `apps/client/test/app/studyflow_app_test.dart`

**Interfaces:**
- Consumes: existing `StudyFlowApp(workspace: workspace)` test harness.
- Produces: assertions that the shell changes navigation at the 900 logical-pixel breakpoint.

- [ ] **Step 1: Write the failing wide-window test**

  Add a widget test that sets the test surface to `1200x800`, pumps `StudyFlowApp`, and asserts one `NavigationRail`, no `NavigationBar`, and visible `Today`/`Settings` labels.

- [ ] **Step 2: Run the focused test and verify it fails**

  Run from `apps/client`:

  ```bash
  bash ../../tool/flutter test test/app/studyflow_app_test.dart --plain-name "wide window uses desktop navigation"
  ```

  Expected failure: `NavigationRail` is not found because the current shell always renders `NavigationBar`.

- [ ] **Step 3: Write the failing narrow-window assertion**

  Add a second widget test using a `600x800` surface that asserts one `NavigationBar` and no `NavigationRail`, preserving the current Android behavior.

- [ ] **Step 4: Run both focused tests**

  ```bash
  bash ../../tool/flutter test test/app/studyflow_app_test.dart --plain-name "window uses"
  ```

  Expected result: the wide-window test fails for the missing rail while the narrow test documents existing behavior.

### Task 2: Implement the responsive desktop shell

**Files:**
- Modify: `apps/client/lib/features/shell/studyflow_shell.dart`

**Interfaces:**
- Consumes: existing `_paths`, localized labels, `widget.child`, and GoRouter navigation.
- Produces: a shell that renders the same destinations through either `NavigationBar` or a desktop `NavigationRail`.

- [ ] **Step 1: Add the desktop breakpoint and shared destinations**

  Keep the existing route list and destination icons. Add a `static const double _desktopBreakpoint = 900` and a helper that builds the six `NavigationRailDestination` values from the same labels/icons used by the mobile bar.

- [ ] **Step 2: Switch the shell with `LayoutBuilder`**

  Wrap the shell body in `LayoutBuilder`. For widths below 900, return the current `Scaffold` with `NavigationBar`. For widths at or above 900, return a `Scaffold` whose body is a `Row` containing a fixed-width `NavigationRail` and an `Expanded` content area.

- [ ] **Step 3: Constrain desktop content width**

  In the desktop branch, wrap `widget.child` in `Center` and `ConstrainedBox(constraints: BoxConstraints(maxWidth: 1200))`. Use `SizedBox.expand`/`Expanded` so narrow desktop windows do not overflow.

- [ ] **Step 4: Run the focused tests and verify they pass**

  ```bash
  bash ../../tool/flutter test test/app/studyflow_app_test.dart --plain-name "window uses"
  ```

  Expected result: both wide and narrow navigation tests pass.

### Task 3: Verify all client behavior and desktop compilation

**Files:**
- Modify: none unless verification reveals a layout error.

**Interfaces:**
- Consumes: the responsive `StudyFlowShell` and existing client test suite.
- Produces: verified Android and macOS client builds without data/config changes.

- [ ] **Step 1: Run shell and app tests**

  ```bash
  cd apps/client
  bash ../../tool/flutter test test/app/studyflow_app_test.dart
  ```

- [ ] **Step 2: Run static analysis**

  ```bash
  bash ../../tool/flutter analyze
  ```

  Expected result: no new analyzer errors.

- [ ] **Step 3: Build/run macOS and check the desktop branch**

  ```bash
  bash ../../tool/flutter run -d macos \
    --dart-define=STUDYFLOW_API_BASE_URL=http://127.0.0.1:8000
  ```

  Expected result: the macOS window shows a left navigation rail at normal width; resizing below 900 logical pixels returns to the bottom navigation.

- [ ] **Step 4: Re-run the Android test command**

  ```bash
  adb reverse tcp:8000 tcp:8000
  bash ../../tool/flutter run -d V2352A \
    --dart-define=STUDYFLOW_API_BASE_URL=http://127.0.0.1:8000
  ```

  Expected result: Android keeps the bottom navigation and existing pages remain usable.

