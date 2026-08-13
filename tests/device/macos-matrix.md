# macOS acceptance matrix

Reference runner for the macOS client (Apple Silicon, darwin/arm64).

Status legend: ✅ expected / observed · ⚠️ degraded · ❌ failed · ⛔ not applicable

## 当前实现（邮箱认证 + 明文 JSON 同步）

| Scenario | Expected | Observed | Log |
|---|---|---|---|
| 邮箱注册 | Create account 注册成功，进入主界面 | ✅ 实测通过（Bundle ID com.enkiud.studyflow） | |
| 邮箱登录 | Sign in 使用同一邮箱可登录 | ✅ 实测通过（密码 Ma***10.，邮箱大小写不敏感） | |
| 密码错误 | 显示"邮箱或密码错误" | ✅ 实测（API 401 Invalid credentials） | |
| 退出登录 | Settings → Sign out 回到登录页 | ✅ 实测通过 | |
| 会话恢复 | 重启应用后自动刷新 token 恢复会话 | 待实测 | |
| 会话过期 | refresh 401 后清理本地并回登录页 | 待实测 | |
| 离线任务创建 | Task saved to local store | 待实测 | |
| 离线日程创建 | Block saved, no sync attempted | 待实测 | |
| 专注会话开始/结束 | Sessions recorded locally | 待实测 | |
| 打卡保存（睡眠/精力/心情） | Saved offline, visible on Today | 待实测 | |
| 网络断开/恢复 | Sync status shows anomaly, retry after reconnect | 待实测 | |
| 跨设备同步 | 与 Android 登录同一邮箱后任务互达 | 待实测（需 Android 设备） | |
| 通知权限 | 点击权限条目弹出系统授权框 | ✅ 实测（NSAlert + requestAuthorization，原生弹窗） | |
| 客户端备份 | 创建/重命名/删除/多选批量删除 | ✅ 实测通过（含 409 上限提示、确认对话框） | |
| 备份配额 | 每账户上限 5 个，满额置灰 | ✅ 实测（按钮置灰 + 上限对话框） | |
| 语言切换 | 设置页可选中文/英文/跟随系统 | ✅ 实测（i18n 中英对照） | |
| 登录限流 | 连续失败 5 次后 429 | ✅ 实测（Retry-After 提示） | |
| AI 设置 | Settings → AI 设置可配置 Base URL/Model/API Key | 待实测 | |
| 睡眠/唤醒 | App relaunches cleanly, local data intact | 待实测 | |

## Known limits

- Native `StudyFlowPlatform.swift` compiled only via analyzer/CI; on-runner
  verification deferred until a complete Xcode/CocoaPods toolchain is
  available on the build machine.
- macOS Focus-mode integration and app/site restrictions are follow-up work;
  the capability contract reports them as unavailable.
- Xcode 签名：已在 Xcode 配置 Team + Automatically manage signing；
  Bundle ID 为 `com.enkiud.studyflow`。
- macOS 权限中"精确闹钟/电池优化/使用情况访问"为移动平台专属，
  点击显示原生 NSAlert 说明不可用。
- 系统 curl（LibreSSL）直连 API 失败是本机 TLS 栈问题；App 走
  Cloudflare Tunnel（BoringSSL）正常。

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
