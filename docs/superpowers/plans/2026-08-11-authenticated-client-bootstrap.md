# StudyFlow 认证客户端闭环实施计划

> **For agentic workers:** This plan is executed inline in the current session because the user explicitly requested no subagents.

**Goal:** 将 Flutter 客户端接入真实账户、设备身份、加密密钥恢复和离线优先同步，同时保留无 API 配置时的本地模式。

**Architecture:** 使用运行时 API 配置和安全存储中的 `AuthContext`，由会话协调器统一管理账户密钥、加密数据库、工作区和同步引擎生命周期。认证 UI 只负责输入和错误呈现，服务端仍是唯一认证与同步入口。

**Tech Stack:** Flutter/Dart, Riverpod, GoRouter, flutter_secure_storage, Drift/sqlite3mc, XChaCha20-Poly1305, existing FastAPI auth/sync API.

## Global Constraints

- API 基地址通过 `--dart-define=STUDYFLOW_API_BASE_URL=...` 传入。
- bootstrap token、密码、访问令牌、refresh token 不提交 Git，不写普通日志，不写入 Dart define。
- 账户数据只通过 `KeyManager` 和账户范围数据库访问。
- 同步网络失败不得丢弃本地 pending operation。
- 每个任务先写失败测试，确认失败后再写生产代码。

---

### Task 1: 固化项目 Flutter 命令入口

**Files:**
- Create: `tool/flutter`
- Modify: `.gitignore`
- Modify: `README.md`
- Test: `tool/test_flutter_wrapper.sh`

- [ ] **Step 1: 写包装器行为测试**

测试项目能够识别项目根目录、设置 `CI=true`、`FLUTTER_SUPPRESS_ANALYTICS=true`、项目内 `PUB_CACHE`，并在 `STUDYFLOW_FLUTTER_ROOT` 指向可执行 SDK 时调用该 SDK。

- [ ] **Step 2: 运行测试确认失败**

运行：`bash tool/test_flutter_wrapper.sh`

预期：因为 `tool/flutter` 尚不存在而失败。

- [ ] **Step 3: 实现包装器**

包装器按以下优先级寻找 Flutter：`STUDYFLOW_FLUTTER_ROOT`、项目 `.tool-cache/flutter-sdk`、`mise which flutter`、系统 PATH；找不到时输出安装指引并退出非零。`.tool-cache/` 和包装器测试临时目录必须被忽略。

- [ ] **Step 4: 运行包装器测试和版本检查**

运行：`bash tool/test_flutter_wrapper.sh`；然后运行：`tool/flutter --version`。

预期：包装器测试通过；若本机 SDK 可用，版本为 mise.toml 的 Flutter 3.44.9。

- [ ] **Step 5: 更新 README 并提交**

README 的客户端命令统一使用 `tool/flutter`，并说明 API 地址的 `--dart-define` 用法。

### Task 2: 增加持久化设备身份和账户密钥导入

**Files:**
- Create: `apps/client/lib/auth/device_identity.dart`
- Modify: `apps/client/lib/security/key_manager.dart`
- Modify: `apps/client/lib/auth/device_enrollment_crypto.dart`
- Test: `apps/client/test/auth/device_identity_test.dart`
- Test: `apps/client/test/auth/account_key_import_test.dart`

- [ ] **Step 1: 写设备 ID 和账户密钥导入测试**

覆盖同一安全存储重复读取返回同一 UUID、不同账户使用不同键名、envelope 解密后的 32 字节密钥可导入、错误账户不能导入。

- [ ] **Step 2: 运行测试确认失败**

运行：`tool/flutter test apps/client/test/auth/device_identity_test.dart apps/client/test/auth/account_key_import_test.dart`。

预期：因为设备身份和密钥导入接口尚不存在而失败。

- [ ] **Step 3: 实现最小安全存储接口**

设备 ID 使用 `flutter_secure_storage` 的独立版本化键；账户密钥导入复用 `KeyManager` 的账户范围校验和持久化逻辑，不允许覆盖不同现有密钥。

- [ ] **Step 4: 运行聚焦测试**

运行同一测试命令，预期全部通过。

### Task 3: 实现认证会话协调器

**Files:**
- Create: `apps/client/lib/auth/client_session.dart`
- Modify: `apps/client/lib/app/studyflow_workspace.dart`
- Modify: `apps/client/lib/sync/sync_engine.dart`
- Test: `apps/client/test/auth/client_session_test.dart`

- [ ] **Step 1: 写会话恢复测试**

覆盖无会话、有效会话、envelope 恢复、错误 envelope、退出关闭旧工作区、网络同步失败保留 pending operation。

- [ ] **Step 2: 运行测试确认失败**

运行：`tool/flutter test apps/client/test/auth/client_session_test.dart`。

预期：协调器不存在而失败。

- [ ] **Step 3: 实现会话协调器**

协调器负责 `AuthRepository`、`KeyManager`、`AccountScopedStore`、`StudyFlowWorkspace`、`HttpSyncApi` 和 `SyncEngine` 的生命周期；启动同步失败只更新 `SyncStatus`。

- [ ] **Step 4: 运行会话和同步聚焦测试**

运行：`tool/flutter test apps/client/test/auth apps/client/test/sync`。

### Task 4: 将认证入口接入 Flutter 主流程

**Files:**
- Create: `apps/client/lib/auth/auth_screen.dart`
- Create: `apps/client/lib/config/client_config.dart`
- Modify: `apps/client/lib/main.dart`
- Modify: `apps/client/lib/auth/auth_repository.dart`
- Test: `apps/client/test/auth/auth_screen_test.dart`
- Test: `apps/client/test/app/studyflow_app_test.dart`

- [ ] **Step 1: 写认证入口测试**

覆盖未配置 API 时显示本地模式入口、配置 API 且无会话时显示 login/pair/bootstrap/recovery、bootstrap token 不出现在安全存储写入值中、有效会话进入 Today。

- [ ] **Step 2: 运行测试确认失败**

运行：`tool/flutter test apps/client/test/auth/auth_screen_test.dart apps/client/test/app/studyflow_app_test.dart`。

- [ ] **Step 3: 增加 bootstrap API 和配置读取**

`AuthApi` 增加 bootstrap 请求；`ClientConfig` 只读取 API URI，校验必须为 HTTPS，localhost 仅允许开发 HTTP。bootstrap token 作为请求参数传入，不写入 `AuthContextStore`。

- [ ] **Step 4: 实现认证页面和路由**

认证成功后打开账户工作区；恢复密钥失败时进入 Recovery 页面；退出时返回认证入口。

- [ ] **Step 5: 运行 UI 和 analyzer**

运行：`tool/flutter test apps/client/test/auth apps/client/test/app/studyflow_app_test.dart`；`tool/flutter analyze`。

### Task 5: 接入同步状态和客户端配置文档

**Files:**
- Modify: `apps/client/lib/features/settings/settings_screen.dart`
- Modify: `apps/client/lib/features/shell/studyflow_shell.dart`
- Modify: `README.md`
- Modify: `apps/client/README.md`
- Test: `apps/client/test/features/settings/settings_screen_test.dart`

- [ ] **Step 1: 写同步状态 UI 测试**

覆盖 idle/syncing/offline/authentication failure 状态的可见文案和 pending 数量。

- [ ] **Step 2: 实现状态展示和手动同步**

设置页显示账户 ID 的尾段、设备 ID 的尾段、同步状态和 pending 数量；不显示 token。提供手动同步按钮。

- [ ] **Step 3: 更新运行说明**

记录：

```bash
tool/flutter run --dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com
```

并明确服务端需要在 VPS `.env` 中填写的配置项：`STUDYFLOW_DATABASE_URL`、`STUDYFLOW_BOOTSTRAP_TOKEN`、`STUDYFLOW_TOKEN_SIGNING_KEY`、`STUDYFLOW_API_HOST`。

- [ ] **Step 4: 运行完整客户端验证并提交**

运行：`tool/flutter test apps/client/test packages/domain/test packages/sync_contract/test`；`tool/flutter analyze`。

### Task 6: 阶段验收和密钥提示

**Files:**
- Modify: `infra/.env.example`
- Modify: `infra/README.md`
- Modify: `docs/superpowers/sdd/2026-08-11-studyflow-mvp/progress.md`

- [ ] **Step 1: 补充安全随机值生成命令**

文档说明使用 `openssl rand -hex 32` 生成 `STUDYFLOW_BOOTSTRAP_TOKEN` 和 `STUDYFLOW_TOKEN_SIGNING_KEY`，以及 Supabase session pooler `:5432` URL 的填写位置。

- [ ] **Step 2: 运行服务端测试**

运行：`cd server && mise exec -- poetry run pytest`。

- [ ] **Step 3: 记录仍需外部条件的验证**

明确 `STUDYFLOW_TEST_DATABASE_URL`、Android SDK、完整 Xcode/CocoaPods 和实际 VPS 凭据未配置时的跳过项，不将其标记为通过。

- [ ] **Step 4: 提交阶段变更**

提交信息：`feat: connect authenticated client session and sync`。
