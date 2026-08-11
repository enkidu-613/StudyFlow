# macOS acceptance matrix

Reference runner for the macOS client (Apple Silicon, darwin/arm64).

Status legend: ✅ expected / observed · ⚠️ degraded · ❌ failed · ⛔ not applicable

## 当前实现（邮箱认证 + 明文 JSON 同步）

| Scenario | Expected | Observed | Log |
|---|---|---|---|
| 邮箱注册 | Create account 注册成功，进入主界面 | | |
| 邮箱登录 | Sign in 使用同一邮箱可登录 | | |
| 密码错误 | 显示"邮箱或密码错误" | | |
| 退出登录 | Settings → Sign out 回到登录页 | | |
| 会话恢复 | 重启应用后自动刷新 token 恢复会话 | | |
| 会话过期 | refresh 401 后清理本地并回登录页 | | |
| 离线任务创建 | Task saved to local store | | |
| 离线日程创建 | Block saved, no sync attempted | | |
| 专注会话开始/结束 | Sessions recorded locally | | |
| 打卡保存（睡眠/精力/心情） | Saved offline, visible on Today | | |
| 网络断开/恢复 | Sync status shows anomaly, retry after reconnect | | |
| 跨设备同步 | 与 Android 登录同一邮箱后任务互达 | | |
| AI 设置 | Settings → AI 设置可配置 Base URL/Model/API Key | | |
| AI Key 隔离 | Key 只在本机安全存储，VPS 无记录 | | |
| 通知授权 | Runtime prompt works, denied state visible | | |
| 睡眠/唤醒 | App relaunches cleanly, local data intact | | |

## Known limits

- Native `StudyFlowPlatform.swift` compiled only via analyzer/CI; on-runner
  verification deferred until a complete Xcode/CocoaPods toolchain is
  available on the build machine.
- macOS Focus-mode integration and app/site restrictions are follow-up work;
  the capability contract reports them as unavailable.
- Xcode 签名：需要在 Xcode 中配置 Team、Automatically manage signing 和
  entitlements；代码仍全部位于 Dart 的 `apps/client/lib/`。

## How to run

```bash
cd apps/client
bash ../../tool/flutter run -d macos \
  --dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com
# or, after toolchain setup:
flutter build macos --debug
```

Record each scenario with: OS/build, permission state, expected, observed,
and a reproducible log location. Failures are capability results, not silent
skips.
