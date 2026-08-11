# Android acceptance matrix — iQOO Z9 Turbo (OriginOS 6)

Reference device for the Android client.

- Device: iQOO Z9 Turbo
- Model: `V2352A`
- System: OriginOS 6 build `PD2352B_A_16.2.15.0.W10.V000L1`
- Kernel: `6.1.145-android14-11-maybe-dirty`
- Security patch: 2026-05-01 (build 2026-06-17)

Status legend: ✅ expected / observed · ⚠️ degraded · ❌ failed · ⛔ not applicable

## 当前实现（邮箱认证 + 明文 JSON 同步）

| Scenario | Expected | Observed | Log |
|---|---|---|---|
| 邮箱注册 | Create account 注册成功，进入主界面 | | |
| 邮箱登录 | Sign in 使用与 macOS 相同的邮箱可登录 | | |
| 密码错误 | 显示"邮箱或密码错误" | | |
| 离线任务创建 | Task saved to local store | | |
| 离线日程创建 | Block saved, no sync attempted | | |
| 专注会话开始/结束 | Sessions recorded locally | | |
| 打卡保存（睡眠/精力/心情） | Saved offline, visible on Today | | |
| 跨设备同步 | 与 macOS 同一邮箱登录后任务互达 | | |
| 锁屏时专注 | Session continues, no crash | | |
| 从最近任务清理 | Reminder/sync state survives or reports degraded | | |
| 重启设备 | Local data intact after relaunch | | |
| 电池优化开启 | Background sync degraded but visible status | | |
| 通知权限（Android 13+） | Runtime prompt works, denied state visible | | |
| 使用情况访问权限 | Shows `permission_missing` until granted | | |
| AI 设置 | Settings → AI 设置可配置 Base URL/Model/API Key | | |
| AI Key 隔离 | 每台设备单独填写自己的 Key，不上传 VPS | | |

## Known limits

- Native `StudyFlowPlatform.kt` compiled only in CI/analyzer; on-device
  verification deferred until the Android SDK toolchain is available on the
  build machine.
- Application/site restriction is not implemented; the permission health
  screen reports the capability as unavailable/experimental.
- Exact-alarm permission (SCHEDULE_EXACT_ALARM) is not yet requested.
- Background-sync guarantees depend on OriginOS 6 app-management settings;
  the app must surface `sync_status` anomalies instead of hiding them.

## How to run

```bash
cd apps/client
bash ../../tool/flutter run \
  --dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com
# 或构建 debug APK 后经 adb 安装：
flutter build apk --debug
adb install build/app/outputs/flutter-apk/app-debug.apk
```

Record each scenario with: OS/build, permission state, expected, observed,
and a reproducible log location. Failures are capability results, not silent
skips; unsupported capabilities are shown in-app as `unsupported` or
`permission_missing`.
