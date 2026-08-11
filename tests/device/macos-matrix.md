# macOS acceptance matrix

Reference runner for the macOS client (Apple Silicon, darwin/arm64).

Status legend: ✅ expected / observed · ⚠️ degraded · ❌ failed · ⛔ not applicable

## MVP-1 (current implementation)

| Scenario | Expected | Observed | Log |
|---|---|---|---|
| Offline task creation | Task saved to encrypted local store | | |
| Offline schedule-block creation | Block saved, no sync attempted | | |
| Focus session start/finish | Sessions recorded locally | | |
| Check-in save (sleep/energy/mood) | Saved offline, visible on Today | | |
| Menu-bar / window status | Shell routes render (Today/Tasks/Schedule/Focus/Settings) | | |
| Notification authorization | Runtime prompt works, denied state visible | | |
| Sleep/wake | App relaunches cleanly, local data intact | | |
| Network loss/recovery | Sync status shows anomaly, retry after reconnect | | |
| App relaunch | Encrypted local store opens with the same account | | |

## Known limits (MVP)

- Native `StudyFlowPlatform.swift` compiled only via analyzer/CI; on-runner
  verification deferred until a complete Xcode/CocoaPods toolchain is
  available on the build machine.
- macOS Focus-mode integration and app/site restrictions are follow-up work;
  the capability contract reports them as unavailable.
- Production account pairing/recovery is not wired into the local shell;
  the offline shell uses a fixed local account/device pair.

## How to run

```bash
flutter run -d macos
# or, after toolchain setup:
flutter build macos --debug
```

Record each scenario with: OS/build, permission state, expected, observed,
and a reproducible log location. Failures are capability results, not silent
skips.
