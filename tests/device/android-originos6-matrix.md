# Android acceptance matrix — iQOO Z9 Turbo (OriginOS 6)

Reference device for the Android client.

- Device: iQOO Z9 Turbo
- Model: `V2352A`
- System: OriginOS 6 build `PD2352B_A_16.2.15.0.W10.V000L1`
- Kernel: `6.1.145-android14-11-maybe-dirty`
- Security patch: 2026-05-01 (build 2026-06-17)

Status legend: ✅ expected / observed · ⚠️ degraded · ❌ failed · ⛔ not applicable

## MVP-1 (current implementation)

| Scenario | Expected | Observed | Log |
|---|---|---|---|
| Offline task creation | Task saved to encrypted local store | | |
| Offline schedule-block creation | Block saved, no sync attempted | | |
| Focus session start/finish | Sessions recorded locally | | |
| Check-in save (sleep/energy/mood) | Saved offline, visible on Today | | |
| Lock screen during focus | Session continues, no crash | | |
| App cleanup from recents | Reminder/sync state survives or reports degraded | | |
| Reboot device | Local data intact after relaunch | | |
| Battery optimization on | Background sync degraded but visible status | | |
| Notification permission (Android 13+) | Runtime prompt works, denied state visible | | |
| Usage-access permission state | Shows `permission_missing` until granted | | |

## Known limits (MVP)

- Native `StudyFlowPlatform.kt` compiled only in CI/analyzer; on-device
  verification deferred until the Android SDK toolchain is available on the
  build machine.
- Application/site restriction is not implemented in MVP-1; the permission
  health screen reports the capability as unavailable/experimental.
- Exact-alarm permission (SCHEDULE_EXACT_ALARM) is not yet requested.
- Background-sync guarantees depend on OriginOS 6 app-management settings;
  the app must surface `sync_status` anomalies instead of hiding them.

## How to run

```bash
# Build a debug APK and install over adb
flutter build apk --debug
adb install build/app/outputs/flutter-apk/app-debug.apk
```

Record each scenario with: OS/build, permission state, expected, observed,
and a reproducible log location. Failures are capability results, not silent
skips; unsupported capabilities are shown in-app as `unsupported` or
`permission_missing`.
