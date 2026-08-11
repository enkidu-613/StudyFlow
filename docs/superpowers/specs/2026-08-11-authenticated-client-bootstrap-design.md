# StudyFlow 认证客户端闭环设计

## 目标

把 Flutter 客户端从固定本地账户壳升级为可恢复的真实账户会话：客户端能够读取安全存储中的账户上下文，按账户打开加密本地数据库，使用真实访问令牌同步，并在没有配置 API 时保留离线本地模式。

## 范围

本阶段包含：

- 运行时 API 地址配置，不把域名、令牌或密码写入源码。
- 设备 UUID 的安全持久化。
- bootstrap、login、pairing、recovery 四种认证入口。
- 从服务端返回的设备密钥 envelope 恢复账户数据密钥。
- 把 `SyncEngine` 接入真实工作区，并提供手动同步和状态展示。
- 账户切换/退出时关闭旧数据库，避免跨账户数据泄露。

本阶段不包含：

- VPS 实际部署和生产 Supabase 凭据配置。
- 具体 AI Provider 的接入。
- Android UsageStats、网站限制、macOS Screen Time 等原生控制能力。

## 设计

### 配置边界

API 基地址使用 Flutter 编译参数：

```text
--dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com
```

该值不是秘密。bootstrap token、用户密码、访问令牌和 refresh token 不进入 Dart define、Git 或普通日志。bootstrap token 只在一次性初始化表单的内存中使用，并直接发送到 HTTPS API。

### 会话恢复

`ClientSessionCoordinator` 负责以下顺序：

1. 创建 `AuthRepository` 和持久化设备 ID。
2. 尝试恢复安全存储中的 `AuthContext`。
3. 若没有会话，显示认证入口；若 API 未配置，打开已有的本地模式。
4. 若有会话，创建 `KeyManager(accountId)`。
5. 若账户密钥不存在，使用 `DeviceEnrollmentCrypto` 解开服务端 envelope，并通过 `KeyManager` 安全写入账户密钥。
6. 以 `accountId`、`deviceId`、`AuthContext` 创建 `StudyFlowWorkspace`。
7. 创建 `HttpSyncApi` 和 `SyncEngine`，应用启动时执行一次同步；网络失败只显示状态，不阻塞本地使用。

### 认证界面

认证页提供四个明确入口：

- 初始化主账户：需要一次性 bootstrap token、密码；token 不持久化。
- 已有设备登录：密码只提交 HTTPS API，不持久化。
- 新设备配对：输入六位配对码，使用本机设备公钥完成配对。
- 恢复密钥：只在本机缺失账户密钥时使用，恢复后重新打开加密数据库。

认证失败必须显示可行动的错误；不自动创建替代账户、不覆盖其他账户密钥。

### 同步边界

同步引擎只接触加密操作和同步元数据。UI 只显示同步状态、待同步数量和错误类别。同步失败不会删除本地操作队列，也不会把解密后的任务内容写入日志。

## 验收标准

- 无 API 地址时，现有本地离线 shell 测试保持通过。
- 有有效会话时，工作区的 `accountId`、`deviceId` 来自 `AuthContext`，不再使用固定 UUID。
- 账户密钥缺失时，只有正确的 envelope 或 recovery key 能打开该账户数据库。
- 退出账户后，旧工作区和同步引擎均被关闭。
- 至少覆盖：会话恢复、envelope 解密、错误账户隔离、bootstrap token 不落盘、同步失败保留本地队列。
- Flutter analyzer、客户端测试、服务端测试全部通过；真实 Supabase 和物理设备验证在部署阶段单独记录。
