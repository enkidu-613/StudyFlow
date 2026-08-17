# Persistent Alarm Acknowledgement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make StudyFlow focus and schedule alarms ring continuously until acknowledged, route notification/app launches to the correct page, and clear native alarm state and notifications after confirmation.

**Architecture:** Android `ReminderReceiver` persists pending alarm records and starts `AlarmRingingService`, which owns looping sound and an ongoing notification. Flutter `PlatformBridge` exposes pending-alarm reads, acknowledgement, and a live event stream; `StudyFlowShell` consumes these events, routes to focus/schedule, and presents the confirmation dialog.

**Tech Stack:** Kotlin Android foreground service, `AlarmManager`, `NotificationChannel`, `SharedPreferences` JSON state, Flutter/Dart `MethodChannel`/`EventChannel`, GoRouter, Flutter widget tests.

## Global Constraints

- Android package remains `com.studyflow.studyflow` and must support Android 16/API 36.
- Existing exact-alarm and notification permission checks remain authoritative.
- The native alarm path is primary; existing in-process timer fallback remains only when native scheduling is unavailable.
- Confirmation must be idempotent and must remove the notification after successful acknowledgement.
- Do not expose secrets or alter unrelated dirty-worktree changes.

---

### Task 1: Define the Flutter pending-alarm contract and failing tests

**Files:**
- Modify: `apps/client/lib/platform/platform_bridge.dart`
- Modify: `apps/client/test/platform/platform_bridge_test.dart`
- Create: `apps/client/lib/features/alarm/pending_alarm.dart`
- Create: `apps/client/test/features/alarm/pending_alarm_test.dart`

**Interfaces:**
- `PendingAlarm({required String id, required String title, required String text, required String kind, String? entityId})`.
- `PlatformBridge.getPendingAlarms() -> Future<List<PendingAlarm>>`.
- `PlatformBridge.acknowledgeAlarm(String id) -> Future<CapabilityResult>`.
- `PlatformBridge.alarmEvents -> Stream<PendingAlarm>`.

- [ ] **Step 1: Add model and bridge tests first.** Assert JSON parsing preserves `id`, `title`, `text`, `kind`, and `entityId`; assert bridge invokes `getPendingAlarms` and `acknowledgeAlarm`; assert an event stream item is decoded.
- [ ] **Step 2: Run the focused tests and verify they fail** because the model and bridge methods do not exist yet.
- [ ] **Step 3: Implement the typed Dart model and bridge methods** with missing-plugin behavior returning an empty list or unsupported capability.
- [ ] **Step 4: Run the focused tests and verify they pass.**

### Task 2: Implement Android persistent pending alarms and continuous ringing

**Files:**
- Modify: `apps/client/android/app/src/main/kotlin/com/studyflow/app/StudyFlowPlatform.kt`
- Modify: `apps/client/android/app/src/main/kotlin/com/studyflow/studyflow/MainActivity.kt`
- Modify: `apps/client/android/app/src/main/AndroidManifest.xml`
- Modify: `apps/client/android/app/build.gradle.kts` only if the Android plugin requires an explicit foreground-service configuration
- Test: `apps/client/android/app/src/test` or existing JVM-compatible Kotlin test location if available

**Interfaces:**
- Native channel methods: `getPendingAlarms`, `acknowledgeAlarm`.
- Native event channel: `studyflow/alarm_events` emits pending alarm maps.
- `AlarmRingingService.start(context, alarmId)` and `AlarmRingingService.stop(context)`.

- [ ] **Step 1: Add the native state/service contract test or compile-safe test fixture** for pending JSON state, acknowledgement idempotence, and notification ID mapping.
- [ ] **Step 2: Run the native test/compile check and verify the new behavior is absent or fails.**
- [ ] **Step 3: Add `AlarmRingingService`** with a foreground notification, looping `Ringtone`/alarm audio, and a stop action callable from `acknowledgeAlarm`.
- [ ] **Step 4: Change `ReminderReceiver`** to save the pending record, start the service, post an ongoing notification with a content intent, and emit a live event when Flutter is connected; do not remove the pending record merely because the alarm fired.
- [ ] **Step 5: Add manifest permissions/receiver-service declarations** required by Android 16 foreground services while retaining `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, and boot rescheduling.
- [ ] **Step 6: Implement `getPendingAlarms` and idempotent `acknowledgeAlarm`** so acknowledgement stops sound, stops the service when no pending alarms remain, cancels the exact notification, and deletes the persisted record.
- [ ] **Step 7: Compile the Android app and verify the native checks pass.**

### Task 3: Route native alarm events into a confirmation dialog

**Files:**
- Modify: `apps/client/lib/platform/platform_bridge.dart`
- Modify: `apps/client/lib/features/shell/studyflow_shell.dart`
- Create: `apps/client/lib/features/alarm/pending_alarm_dialog.dart`
- Modify: `apps/client/lib/main.dart` only if lifecycle wiring needs a root callback
- Test: `apps/client/test/features/shell/studyflow_shell_test.dart`

**Interfaces:**
- `PendingAlarmDialog` accepts a `PendingAlarm` and an acknowledgement callback.
- Shell calls `getPendingAlarms` on init and `AppLifecycleState.resumed`, and listens to `alarmEvents` while mounted.

- [ ] **Step 1: Add widget tests** for startup pending alarm, live event, correct `/focus` and `/schedule` routing, explicit acknowledgement, and no duplicate dialog for the same ID.
- [ ] **Step 2: Run the widget tests and verify they fail** before shell integration exists.
- [ ] **Step 3: Implement the dialog** with the alarm title/time, `完成`/`关闭并记录` action, non-dismissible barrier, and a loading state that prevents double acknowledgement.
- [ ] **Step 4: Integrate shell lifecycle/event handling**; when an alarm is discovered, route first and show the dialog; after the callback succeeds, remove it from the local queue.
- [ ] **Step 5: Run shell and existing Flutter tests and verify they pass.**

### Task 4: Connect focus/schedule acknowledgement and verify on V2352A

**Files:**
- Modify: `apps/client/lib/features/focus/focus_screen.dart` only for focus-specific completion refresh if required by the dialog flow
- Modify: `apps/client/lib/features/schedule/schedule_completion_service.dart` only if the pending alarm must create a completion event
- Modify: `apps/client/lib/features/schedule/schedule_alarm_service.dart` only to preserve identifiers through acknowledgement
- Test: `apps/client/test/features/focus/focus_screen_test.dart`
- Test: `apps/client/test/features/schedule/schedule_alarm_service_test.dart`

- [ ] **Step 1: Add regression tests** proving a focus or schedule alarm remains pending after firing and is cleared only by acknowledgement.
- [ ] **Step 2: Run those tests and verify the pre-change behavior fails.**
- [ ] **Step 3: Implement the smallest domain integration** so the generic dialog uses existing schedule feedback and focus history paths without duplicating records.
- [ ] **Step 4: Run `dart format`, `flutter analyze`, all focused tests, and `flutter build apk --debug`.**
- [ ] **Step 5: Install on V2352A and verify:** start a one-minute focus task, wait for notification/sound, open notification, submit dialog, confirm notification removal; repeat with a schedule alarm or a native test alarm.
- [ ] **Step 6: Capture `dumpsys notification`, `dumpsys activity`, and `logcat` evidence, then leave the repaired debug APK installed.**
