# StudyFlow 本地 PostgreSQL 与邮箱认证简化实施计划

> **For agentic workers:** 直接按本计划的任务和检查点执行；本项目默认不使用子代理。步骤使用复选框（`- [ ]`）跟踪。

**Goal:** 将 StudyFlow 从 Supabase + bootstrap/device 加密认证改造成由 VPS 本地 PostgreSQL 提供数据、以邮箱和密码注册登录、由客户端保存用户自有 AI 配置的简洁 MVP。

**Architecture:** Flutter 是唯一主客户端，负责邮箱注册、登录、本地离线缓存和 AI 调用；Caddy 负责 HTTPS；FastAPI 负责认证、同步和业务 API；PostgreSQL 仅通过 Docker 内网提供给 FastAPI。用户数据由 JWT 中的 `user_id` 关联，客户端不再提交或依赖设备配对身份。

**Tech Stack:** Flutter/Dart、Riverpod、Drift/SQLite、`flutter_secure_storage`、FastAPI、SQLAlchemy Async、asyncpg、Alembic、Argon2id、PyJWT、PostgreSQL、Docker Compose、Caddy、mise。

## Global Constraints

- 不再使用 Supabase URL、Supabase key、Supavisor、Supabase Auth 或 Supabase PostgreSQL。
- 生产环境删除 `STUDYFLOW_BOOTSTRAP_TOKEN`；该变量不得再出现在 Compose、服务端启动校验或客户端请求中。
- 注册字段为邮箱和密码；v1 不发送验证邮件，也不提供邮件找回密码。
- 密码只保存 Argon2id 哈希，原文不写入日志、数据库或客户端文件。
- access token 使用短期 JWT，refresh token 只保存哈希并支持撤销。
- 所有业务数据通过 JWT 的 `user_id` 关联，禁止信任客户端传入的用户 ID。
- v1 移除 bootstrap token、Pair、Recovery key、设备公钥、加密信封和端到端数据加密。
- 同步载荷使用 HTTPS 传输并以 PostgreSQL JSONB 保存；数据库备份仍使用加密备份。
- AI Base URL、模型名和 API Key 由用户在客户端设置；API Key 只进入系统安全存储，不上传 VPS。
- Caddy 保留为 HTTPS 入口；PostgreSQL 不发布到公网，也不发布到宿主机公网端口。
- 当前 macOS curl/Flutter TLS reset 是独立网络问题，必须在认证重构后用独立测试记录，不通过修改认证逻辑掩盖。
- 如果旧 Supabase 中存在需要保留的数据，部署前做一次独立加密归档；没有需要保留的数据时不阻塞本地开发。旧版加密同步载荷不自动转换为新版 JSONB 数据。
- Flutter 作为 Android、macOS、iOS、Windows、Linux 的唯一主客户端；本轮不迁移 React Native，也不引入 Tauri 主窗口。
- 如果未来需要全局快捷键、活动窗口监测或系统托盘，Tauri 只能作为独立桌面辅助进程，不能替换 Flutter 主客户端。
- MVP 只要求编写 Dart/Flutter；不新增 Swift、Kotlin、Rust 或 Xcode 原生业务代码。Xcode 只用于 macOS 构建、签名和权限配置，Android 原生目录只保留现有桥接。
- 每个任务的提交命令由代理执行，用户不需要手动重复执行十次 `git add`/`git commit`。

## 用户只需要自己提供的配置

| 配置 | 由谁提供 | 在哪里填写 | 是否上传服务端 |
|---|---|---|---|
| `STUDYFLOW_API_HOST` | 用户已有的 Cloudflare 域名，例如 `api.example.com` | VPS 的 `infra/.env` | 公开地址 |
| `STUDYFLOW_API_BASE_URL` | 由上面的域名组成，例如 `https://api.example.com` | Flutter 启动参数或客户端配置 | 公开地址 |
| `AI_BASE_URL` | 用户选择的 AI 服务商文档 | 客户端“设置 → AI” | 否 |
| `AI_MODEL` | 用户选择的模型名 | 客户端“设置 → AI” | 否 |
| `AI_API_KEY` | 用户在 AI 服务商控制台创建 | 客户端“设置 → AI” | 否 |

PostgreSQL 密码和 JWT 签名密钥由 VPS 上的 `infra/bootstrap-env.sh` 自动生成并写入权限为 `600` 的 `.env`；备份口令优先由用户从密码管理器提供，没有提供时由脚本生成并只显示一次，用户必须立即保存到 VPS 之外。部署文档必须说明生成命令、保存位置和用途，用户不需要自行猜测这些值。

## 建议执行顺序

不要一次性执行全部十个任务，按下面四个可验收里程碑推进；每个里程碑通过后再进入下一个：

1. **服务端基础**：Task 1（仅在需要保留旧数据时执行）→ Task 2 → Task 3 → Task 4。结果是本地 PostgreSQL、邮箱注册登录和 JWT 会话可独立运行。
2. **客户端核心**：Task 5 → Task 6 → Task 7。结果是 Flutter/Dart 客户端可以登录、退出和同步；不新增 Swift/Kotlin。
3. **客户端 AI**：Task 8。结果是每台设备在设置页独立填写 Base URL、Model 和 API Key，服务端没有 AI 密钥和 AI 路由。
4. **部署验收**：Task 9 → Task 10。结果是 VPS、域名、HTTPS、Android OriginOS 6 和 macOS 首轮流程都有证据。

每个里程碑只学习和修改当前需要的技术；Xcode 签名问题只在第四个里程碑处理，不阻塞前面 Dart/服务端测试。

## 前端技术路线锁定

本计划采用 Flutter 单客户端路线。当前仓库已经具备 Flutter 客户端、Drift/SQLite、本地平台契约、Android Kotlin 桥接和 macOS Swift 桥接；这些现有桥接仅作为仓库现状保留，本轮不要求用户编写或扩展 Swift/Kotlin。

React Native + Tauri 不属于本轮替代方案：它会形成“手机 React Native + 桌面 WebView/Tauri”的两套 UI 运行时，无法减少本项目的原生权限和平台适配工作。未来若桌面接管能力超过 Flutter 插件能力，只新增 `desktop-agent` 辅助进程，使用本地 IPC 或 HTTP 与 Flutter 通信，不重写主 UI。

## 文件与职责总览

**创建：**

- `infra/bootstrap-env.sh`：在 VPS 生成生产 `.env`、随机密钥和数据库连接配置。
- `server/migrations/versions/004_local_email_auth.py`：用户、邮箱唯一约束和会话表迁移。
- `server/migrations/versions/005_plaintext_sync_operations.py`：新版 JSONB 同步载荷迁移。
- `server/app/auth/password_policy.py`：邮箱规范化和密码策略。
- `apps/client/lib/auth/email_auth_models.dart`：客户端注册、登录和会话模型。
- `apps/client/lib/features/ai/ai_settings_model.dart`：AI 配置读取、保存和连通性测试模型。
- `apps/client/lib/features/ai/ai_settings_screen.dart`：AI Base URL、模型和 API Key 设置界面。
- `server/tests/test_auth_email.py`：邮箱注册、登录、刷新和撤销测试。
- `server/tests/test_local_postgres_config.py`：本地 PostgreSQL 配置测试。
- `apps/client/test/auth/email_auth_screen_test.dart`：客户端认证界面测试。
- `apps/client/test/features/ai/ai_settings_test.dart`：AI 配置保存和脱敏测试。

**修改：**

- `server/app/db/config.py`、`server/app/db/models.py`、`server/app/db/context.py`、`server/app/db/repositories.py`：切换本地数据库模型和 `UserContext`。
- `server/app/auth/models.py`、`server/app/auth/service.py`、`server/app/auth/dependencies.py`、`server/app/auth/routes.py`：替换 bootstrap/device 认证为邮箱认证。
- `server/app/main.py`：加载新的认证服务和数据库配置。
- `server/app/sync/schemas.py`、`server/app/sync/repository.py`、`server/app/sync/service.py`、`server/app/sync/routes.py`：移除设备身份并保存 JSONB 载荷。
- `server/tests/test_db_config.py`、`server/tests/test_db_schema.py`、`server/tests/test_sync_service.py`、`server/tests/test_sync_schemas.py`：更新新数据库和同步契约。
- `infra/docker-compose.yml`、`infra/.env.example`、`infra/backup/backup.sh`、`infra/backup/restore-check.sh`、`infra/README.md`：加入本地 PostgreSQL 和新的部署流程。
- `apps/client/lib/auth/auth_repository.dart`、`apps/client/lib/auth/client_auth_controller.dart`、`apps/client/lib/auth/auth_screen.dart`、`apps/client/lib/auth/client_session.dart`、`apps/client/lib/main.dart`：改成邮箱注册/登录。
- `apps/client/lib/sync/sync_api.dart`、`apps/client/lib/sync/sync_engine.dart`、`apps/client/lib/sync/sync_status.dart`：移除设备头和客户端解密流程。
- `apps/client/lib/features/settings/settings_screen.dart`、`apps/client/lib/features/ai/ai_repository.dart`、`apps/client/pubspec.yaml`：加入 AI 配置并移除恢复密钥入口。
- `README.md`、`tests/integration/test_deployed_health.py`、`tests/device/macos-matrix.md`、`tests/device/android-originos6-matrix.md`：更新启动参数、测试流程和部署说明。

本轮不创建 React Native、Tauri 或 Rust 主客户端目录；任何桌面辅助进程需求必须另立设计和计划。

**删除或停止引用：**

- `apps/client/lib/auth/device_enrollment_crypto.dart`
- `apps/client/lib/auth/device_identity.dart`
- `apps/client/lib/auth/pairing_screen.dart`
- `apps/client/lib/auth/recovery_key_screen.dart`
- `apps/client/lib/security/key_manager.dart`
- `apps/client/lib/security/payload_cipher.dart`
- `server/app/ai/routes.py`、`server/app/ai/service.py`、`server/app/ai/provider.py`、`server/app/ai/models.py`、`server/app/ai/redaction.py` 及 `server/tests/test_ai_gateway.py`
- 旧的 `BootstrapRequest`、`PairDeviceRequest`、`CreatePairingCodeRequest`、`RevokeDeviceRequest` 及对应 API 路由。

---

### Task 1: 固化迁移边界与可选旧数据归档

**Files:**

- Modify: `infra/backup/backup.sh`
- Modify: `infra/backup/restore-check.sh`
- Modify: `infra/README.md`
- Create: `docs/superpowers/specs/2026-08-12-local-postgres-migration-boundary.md`

**Interfaces:**

- Consumes: 仅在确实需要保留旧数据时使用临时的 `OLD_DATABASE_URL` 和 `STUDYFLOW_BACKUP_PASSPHRASE`。
- Produces: 已验证的加密备份，以及“旧版数据不自动解密迁移”的明确说明。

- [ ] **Step 1: 明确旧数据策略**

在迁移说明中写明：如果旧 Supabase 有重要数据，先完成 `pg_dump` 加密备份；如果没有重要数据，记录“本次不迁移旧数据”，直接让新版本地数据库以干净 schema 启动。旧版 `payload_nonce/payload_ciphertext` 只保留在备份中，不在本计划内尝试恢复为明文。

- [ ] **Step 2: 修正备份脚本的数据库 URL 说明**

保持 `pg_dump --dbname="$DATABASE_URL"` 的行为，但要求临时变量 `OLD_DATABASE_URL` 使用标准 `postgresql://` URL，避免将 `postgresql+asyncpg://` 传给 PostgreSQL CLI；不要把旧 Supabase URL 写入新的生产 `.env`。

- [ ] **Step 3: 运行备份完整性检查**

运行：

```bash
cd /home/studyflow/app/infra
export STUDYFLOW_DATABASE_URL="$OLD_DATABASE_URL"
./backup/backup.sh
backup_artifact="$(find /var/backups/studyflow -maxdepth 1 -type f -name 'studyflow-*.gpg' -print | sort | tail -n 1)"
test -n "$backup_artifact"
./backup/restore-check.sh "$backup_artifact"
```

仅在选择保留旧数据时执行；执行前必须在当前 shell 中设置 `OLD_DATABASE_URL` 和 `STUDYFLOW_BACKUP_PASSPHRASE`。Expected：备份生成，恢复检查输出 `Decryption and digest verified`，且不打印数据库密码或备份口令。

- [ ] **Step 4: Commit**

```bash
git add infra/backup infra/README.md docs/superpowers/specs/2026-08-12-local-postgres-migration-boundary.md
git commit -m "docs: define local database migration boundary"
```

### Task 2: 加入 VPS 内网 PostgreSQL

**Files:**

- Modify: `infra/docker-compose.yml`
- Modify: `infra/.env.example`
- Modify: `server/app/db/config.py`
- Modify: `server/tests/test_db_config.py`
- Create: `server/tests/test_local_postgres_config.py`

**Interfaces:**

- Consumes: `STUDYFLOW_POSTGRES_DB`、`STUDYFLOW_POSTGRES_USER`、`STUDYFLOW_POSTGRES_PASSWORD`、`STUDYFLOW_DATABASE_URL`。
- Produces: Docker Compose 内名为 `postgres` 的 PostgreSQL 服务，以及 FastAPI 可使用的本地连接 URL。

- [ ] **Step 1: 先写数据库配置失败测试**

覆盖以下输入：

```python
assert normalize_database_url(
    "postgresql://studyflow:secret@postgres:5432/studyflow"
) == "postgresql+asyncpg://studyflow:secret@postgres:5432/studyflow"
```

并验证 Supabase pooler 主机名、`postgres` 超级用户和 SQLite URL 被新配置策略拒绝。

- [ ] **Step 2: 添加 PostgreSQL 服务**

在 Compose 中加入：

```yaml
postgres:
  image: postgres:16-alpine
  restart: unless-stopped
  environment:
    POSTGRES_DB: ${STUDYFLOW_POSTGRES_DB}
    POSTGRES_USER: ${STUDYFLOW_POSTGRES_USER}
    POSTGRES_PASSWORD: ${STUDYFLOW_POSTGRES_PASSWORD}
  volumes:
    - studyflow_postgres:/var/lib/postgresql/data
  networks:
    - studyflow
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
    interval: 10s
    timeout: 5s
    retries: 5
```

API 只通过 `postgres:5432` 访问，Compose 不添加 `5432:5432` 端口映射。

- [ ] **Step 3: 让 API 等待数据库健康**

为 `api` 增加 `depends_on` 的健康条件，并将连接 URL 改为：

`bootstrap-env.sh` 写入完整的 `postgresql://` 连接 URL，其中密码是已经生成的十六进制值；不要把 `${STUDYFLOW_POSTGRES_PASSWORD}` 这种 Shell 表达式原样写进生产 `.env`。服务端启动时再将该标准 URL 转为 `postgresql+asyncpg://`。

- [ ] **Step 4: 更新环境变量测试**

运行：

```bash
cd server
mise exec -- poetry run pytest tests/test_db_config.py tests/test_local_postgres_config.py -q
```

Expected：所有本地 PostgreSQL URL 测试通过，Supabase 专用校验不再存在。

- [ ] **Step 5: Commit**

```bash
git add infra/docker-compose.yml infra/.env.example server/app/db/config.py server/tests/test_db_config.py server/tests/test_local_postgres_config.py
git commit -m "feat: run StudyFlow on local PostgreSQL"
```

### Task 3: 建立邮箱用户和会话模型

**Files:**

- Modify: `server/app/db/models.py`
- Modify: `server/app/auth/models.py`
- Modify: `server/app/db/context.py`
- Create: `server/app/auth/password_policy.py`
- Create: `server/migrations/versions/004_local_email_auth.py`
- Create: `server/migrations/versions/005_plaintext_sync_operations.py`
- Test: `server/tests/test_db_schema.py`

**Interfaces:**

- Produces: `UserContext(user_id: UUID, email: str)`。
- Produces: `POST /v1/auth/register`、`POST /v1/auth/login`、`POST /v1/auth/refresh`、`POST /v1/auth/logout` 所需的 SQLAlchemy 模型。

- [ ] **Step 1: 定义用户表**

将现有 `Account` 重构为用户账户表，至少包含：

```text
user_id UUID PRIMARY KEY
email VARCHAR(320) NOT NULL
email_normalized VARCHAR(320) NOT NULL UNIQUE
password_hash VARCHAR(512) NOT NULL
created_at TIMESTAMPTZ NOT NULL
updated_at TIMESTAMPTZ NOT NULL
```

邮箱比较统一使用 `strip().casefold()`，数据库唯一约束使用 `email_normalized`。

- [ ] **Step 2: 定义会话表**

保留 refresh token 轮换思想，但移除 `device_id` 外键：

```text
session_id UUID PRIMARY KEY
user_id UUID REFERENCES users(user_id) ON DELETE CASCADE
token_digest BYTEA UNIQUE NOT NULL
expires_at TIMESTAMPTZ NOT NULL
revoked_at TIMESTAMPTZ NULL
replacement_session_id UUID NULL
created_at TIMESTAMPTZ NOT NULL
```

- [ ] **Step 3: 定义 JSONB 同步表**

新增新版同步表，避免破坏旧的加密同步记录：

```text
server_sequence BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY
user_id UUID REFERENCES users(user_id) ON DELETE CASCADE
operation_id UUID NOT NULL
record_id UUID NOT NULL
logical_clock BIGINT NOT NULL
entity_type VARCHAR(32) NOT NULL
payload JSONB NOT NULL
is_tombstone BOOLEAN NOT NULL DEFAULT FALSE
schema_version INTEGER NOT NULL DEFAULT 1
created_at TIMESTAMPTZ NOT NULL
UNIQUE(user_id, operation_id)
```

- [ ] **Step 4: 编写 Alembic 迁移**

迁移必须在干净本地 PostgreSQL 上通过 `alembic upgrade head`；对旧 Supabase 数据不执行静默删除。若需要在包含旧表的数据库上运行，迁移只新增新版表，不删除旧表。

- [ ] **Step 5: 运行 schema 测试**

```bash
cd server
mise exec -- poetry run pytest tests/test_db_schema.py tests/test_migration_config.py -q
```

Expected：用户邮箱唯一、会话外键、JSONB 载荷和所有检查约束通过。

- [ ] **Step 6: Commit**

```bash
git add server/app/db server/app/auth/models.py server/app/auth/password_policy.py server/migrations/versions/004_local_email_auth.py server/migrations/versions/005_plaintext_sync_operations.py server/tests/test_db_schema.py
git commit -m "feat: add local email account schema"
```

### Task 4: 实现邮箱注册、登录和会话撤销

**Files:**

- Modify: `server/app/auth/service.py`
- Modify: `server/app/auth/routes.py`
- Modify: `server/app/auth/dependencies.py`
- Modify: `server/app/auth/models.py`
- Modify: `server/app/main.py`
- Create: `server/tests/test_auth_email.py`
- Delete or replace: `server/tests/test_auth_and_pairing.py`

**Interfaces:**

- `POST /v1/auth/register` accepts `{email, password}` and returns `201` with a session.
- `POST /v1/auth/login` accepts `{email, password}` and returns `200` with a session.
- `POST /v1/auth/refresh` accepts `{refresh_token}` and rotates the session.
- `POST /v1/auth/logout` revokes the presented refresh token and returns `204`.
- `GET /v1/auth/session` returns `{user_id, email}` for a valid bearer token.

- [ ] **Step 1: 写注册失败测试**

测试以下行为：重复邮箱返回 `409`；无效邮箱返回 `422`；少于 12 个字符的密码返回 `422`；注册成功返回 `201`，并且响应不包含 `password_hash`。

- [ ] **Step 2: 写登录和会话测试**

测试：正确邮箱密码返回 token；邮箱大小写变化仍可登录；错误密码统一返回 `401 Invalid credentials`；刷新 token 轮换成功；旧 refresh token 再次使用返回 `401`；注销后 refresh token 失效。

- [ ] **Step 3: 实现邮箱与密码策略**

在 `password_policy.py` 中提供：

```python
def normalize_email(value: str) -> str: ...
def validate_password(value: str) -> str: ...
```

邮箱长度限制为 320；密码长度限制为 12 到 256；Argon2id 参数继续由 `argon2-cffi` 管理，并在登录时支持 `check_needs_rehash`。

- [ ] **Step 4: 修改 JWT 身份**

JWT 使用 `sub=user_id`、`email`、`type=access`、`iss=studyflow-api`、`aud=studyflow-client`、`iat`、`exp` 和 `jti`；删除 `device_id` claim。依赖注入返回 `UserContext`，不再要求 `X-Device-Id`。

- [ ] **Step 5: 运行认证测试**

```bash
cd server
mise exec -- poetry run pytest tests/test_auth_email.py -q
```

Expected：注册、登录、刷新、注销、错误凭据和重复邮箱测试全部通过。

- [ ] **Step 6: Commit**

```bash
git add server/app/auth server/app/main.py server/tests/test_auth_email.py
git commit -m "feat: add email and password authentication"
```

### Task 5: 重写用户数据同步边界

**Files:**

- Modify: `server/app/sync/schemas.py`
- Modify: `server/app/sync/repository.py`
- Modify: `server/app/sync/service.py`
- Modify: `server/app/sync/routes.py`
- Modify: `server/app/db/repositories.py`
- Modify: `server/app/db/context.py`
- Create: `server/tests/test_plaintext_sync.py`
- Modify: `server/tests/test_sync_schemas.py`
- Modify: `server/tests/test_sync_service.py`

**Interfaces:**

- `SyncOperationV2` 使用 `userId` 不出现在请求体中；服务端从 bearer token 读取用户身份。
- 请求载荷字段为 `payload: object`，最大序列化大小为 256 KiB。
- `/v1/sync/push` 和 `/v1/sync/pull` 继续保留 cursor、批量大小和幂等操作 ID。

- [ ] **Step 1: 写 JSONB 同步契约测试**

验证：缺少 `operationId`、错误 `entityType`、超过 256 KiB、非法 `schemaVersion` 返回 422；请求中的 `userId` 即使存在也被拒绝或忽略；服务端只使用认证用户。

- [ ] **Step 2: 实现新版 Pydantic schema**

载荷使用 `dict[str, object]`，接受任务、日程、专注和打卡四种实体；tombstone 操作允许 `payload={}`；不再有 `payloadNonce`、`payloadCiphertext`、`deviceId`。

- [ ] **Step 3: 实现服务端归属检查**

仓储查询必须包含 `WHERE user_id = :authenticated_user_id`；重复的 `(user_id, operation_id)` 返回 duplicates；相同 operation ID 但 payload 不同返回 409。

- [ ] **Step 4: 运行同步测试**

```bash
cd server
mise exec -- poetry run pytest tests/test_plaintext_sync.py tests/test_sync_schemas.py tests/test_sync_service.py -q
```

Expected：两个不同用户无法读取或覆盖对方同步记录，且同一用户的幂等和 cursor 行为保持正确。

- [ ] **Step 5: Commit**

```bash
git add server/app/sync server/app/db/repositories.py server/tests/test_plaintext_sync.py server/tests/test_sync_schemas.py server/tests/test_sync_service.py
git commit -m "feat: scope sync data by user and store JSON payloads"
```

### Task 6: 重做 Flutter 邮箱认证界面

**Files:**

- Modify: `apps/client/lib/auth/auth_repository.dart`
- Modify: `apps/client/lib/auth/client_auth_controller.dart`
- Modify: `apps/client/lib/auth/auth_screen.dart`
- Modify: `apps/client/lib/auth/client_session.dart`
- Modify: `apps/client/lib/main.dart`
- Create: `apps/client/lib/auth/email_auth_models.dart`
- Create: `apps/client/test/auth/email_auth_screen_test.dart`
- Modify: `apps/client/test/auth/auth_screen_test.dart`

**Interfaces:**

- `AuthContext` 只包含 `userId`、`email`、`accessToken`、`refreshToken`、`expiresIn`。
- `AuthApi.register(email, password)`、`AuthApi.login(email, password)`、`AuthApi.refresh(refreshToken)`、`AuthApi.logout(refreshToken)`。
- 客户端安全存储只保存 token 和用户邮箱，不保存密码。

- [ ] **Step 1: 写界面测试**

验证初始界面只显示 `Sign in` 和 `Create account`；注册模式显示邮箱、密码、确认密码；登录模式只显示邮箱和密码；页面中不出现 `Initialize`、`Pair`、`Recovery key` 或 `bootstrap token`。

- [ ] **Step 2: 实现邮箱注册与登录请求**

请求路径固定为 `/v1/auth/register` 和 `/v1/auth/login`；统一处理 401、409、422、网络错误和连接重置，并显示可读的中文提示。

- [ ] **Step 3: 实现会话持久化**

启动时读取安全存储中的 refresh token；有效则刷新会话；刷新失败则清理 token 并回到登录页。退出登录时调用服务端 logout，再清除本地 token。

- [ ] **Step 4: 删除旧初始化入口**

从 `AuthScreen`、`main.dart` 和路由中删除 bootstrap、pair、recovery、local-mode 入口；无 API Base URL 时直接显示配置错误，而不是静默进入本地模式。

- [ ] **Step 5: 运行 Flutter 测试**

```bash
cd apps/client
bash ../../tool/flutter test test/auth/auth_screen_test.dart test/auth/email_auth_screen_test.dart
```

Expected：认证界面测试通过，且不存在依赖 VPS 运维密钥的控件。

- [ ] **Step 6: Commit**

```bash
git add apps/client/lib/auth apps/client/lib/main.dart apps/client/test/auth
git commit -m "feat: replace bootstrap UI with email account flow"
```

### Task 7: 简化客户端同步和本地数据加密边界

**Files:**

- Modify: `apps/client/lib/sync/sync_api.dart`
- Modify: `apps/client/lib/sync/sync_engine.dart`
- Modify: `apps/client/lib/sync/sync_status.dart`
- Modify: `apps/client/lib/app/studyflow_workspace.dart`
- Modify: `apps/client/lib/storage/app_database.dart`
- Modify: `apps/client/lib/storage/tables.dart`
- Modify: `apps/client/pubspec.yaml`
- Delete: `apps/client/lib/security/key_manager.dart`
- Delete: `apps/client/lib/security/payload_cipher.dart`
- Delete: `apps/client/lib/auth/device_enrollment_crypto.dart`
- Delete: `apps/client/lib/auth/device_identity.dart`
- Delete: `apps/client/lib/auth/pairing_screen.dart`
- Delete: `apps/client/lib/auth/recovery_key_screen.dart`
- Modify: related files under `apps/client/test/sync/` and `apps/client/test/features/settings/`

**Interfaces:**

- `SyncEngine` 接收 `AuthContext` 和 `AccountScopedStore`，不再接收 `PayloadCipher`。
- `SyncOperation` 载荷为 JSON 对象，应用本地数据库按 `userId` 隔离。
- HTTP 请求只发送 `Authorization: Bearer access-token` 格式的 bearer 头，不发送 `X-Device-Id`。

- [ ] **Step 1: 写同步客户端失败测试**

验证 push JSON payload 能被序列化；header 不包含 `X-Device-Id`；401 会触发 refresh；远端 payload 能被任务、日程、专注和打卡模型解析。

- [ ] **Step 2: 移除客户端加密调用**

将 `SyncEngine` 中的 `_cipher.encrypt/decrypt` 替换为 JSON 编解码；保留现有冲突合并和 cursor 逻辑；把 `SyncDecryptionFailure` 改为 `SyncPayloadFailure`。

- [ ] **Step 3: 按 userId 隔离本地数据库**

本地表增加当前用户范围；用户退出或切换账户时停止同步并清理当前会话缓存，禁止把上一账户的数据展示给下一账户。

- [ ] **Step 4: 删除恢复密钥和设备配对依赖**

设置页删除恢复密钥卡片；账户登录成功后直接创建或打开该邮箱对应的本地工作区。

- [ ] **Step 5: 运行同步和客户端全量测试**

```bash
cd apps/client
bash ../../tool/flutter test
```

Expected：所有测试通过，代码中不再出现 `bootstrap`、`pairing`、`encryptedAccountDataKeyEnvelope` 和 `X-Device-Id` 的生产路径引用。

- [ ] **Step 6: Commit**

```bash
git add apps/client/lib apps/client/pubspec.yaml apps/client/test
git commit -m "refactor: simplify client sessions and sync payloads"
```

### Task 8: 增加客户端 AI 配置

**Files:**

- Create: `apps/client/lib/features/ai/ai_settings_model.dart`
- Create: `apps/client/lib/features/ai/ai_settings_screen.dart`
- Modify: `apps/client/lib/features/ai/ai_repository.dart`
- Modify: `apps/client/lib/features/ai/recommendation_screen.dart`
- Modify: `apps/client/lib/features/settings/settings_screen.dart`
- Modify: `apps/client/pubspec.yaml`
- Modify: `server/app/main.py`
- Delete: `server/app/ai/routes.py`
- Delete: `server/app/ai/service.py`
- Delete: `server/app/ai/provider.py`
- Delete: `server/app/ai/models.py`
- Delete: `server/app/ai/redaction.py`
- Delete: `server/tests/test_ai_gateway.py`
- Create: `apps/client/test/features/ai/ai_settings_test.dart`

**Interfaces:**

- `AiSettings` 包含 `baseUrl`、`model`、`apiKey`、`enabled`。
- `AiSettingsStore.read()`、`AiSettingsStore.write(AiSettings)`、`AiSettingsStore.clear()`。
- `AiRepository.testConnection(settings)` 返回明确的成功或失败原因；AI 请求只从客户端发出，服务端不再暴露 `/v1/ai`。

- [ ] **Step 1: 写安全存储测试**

验证 API Key 通过 `flutter_secure_storage` 写入，日志和 `toString()` 不包含 API Key；读取后能还原 Base URL、模型和开关状态。

- [ ] **Step 2: 添加 OpenAI-compatible 请求适配器**

接受 `https://provider.example/v1` 这类 OpenAI-compatible Base URL，保留用户填写的 `/v1` 路径，再请求其 `/chat/completions`；请求头使用用户 API Key；响应只解析需要的文本或结构化建议。不得把 API Key 放入 URL、日志或异常文本。

- [ ] **Step 3: 加入设置界面**

设置页新增 AI 配置卡片：Base URL、Model、API Key、启用开关和“测试连接”。保存前校验 HTTPS；仅允许本机回环地址使用 HTTP。

- [ ] **Step 4: 改造推荐流程**

未配置 AI 时显示“请先在设置中配置”；配置后由客户端直接调用 AI；从 `server/app/main.py` 移除 AI provider、AI service 和 `/v1/ai` 路由，避免用户误以为服务端需要 AI 密钥。

- [ ] **Step 5: 运行 AI 测试**

```bash
cd apps/client
bash ../../tool/flutter test test/features/ai/ai_settings_test.dart
```

Expected：保存、读取、测试连接失败提示和 API Key 脱敏测试通过。

- [ ] **Step 6: Commit**

```bash
git add apps/client/lib/features/ai apps/client/lib/features/settings/settings_screen.dart apps/client/pubspec.yaml server/app/main.py server/app/ai server/tests/test_ai_gateway.py apps/client/test/features/ai
git commit -m "feat: add per-device AI provider settings"
```

### Task 9: 更新部署、备份和环境变量

**Files:**

- Create: `infra/bootstrap-env.sh`
- Modify: `infra/.env.example`
- Modify: `infra/docker-compose.yml`
- Modify: `infra/api.Dockerfile`
- Modify: `infra/Caddyfile`
- Modify: `infra/README.md`
- Modify: `infra/backup/backup.sh`
- Modify: `infra/backup/restore-check.sh`
- Modify: `README.md`
- Modify: `tests/integration/test_deployed_health.py`

**Interfaces:**

- VPS 只需要本地 PostgreSQL、FastAPI、Caddy 三个容器。
- 客户端只接收公开的 API Base URL，不接收数据库密码、JWT 签名密钥或 AI Key。

- [ ] **Step 1: 重写 `.env.example`**

只保留：

```env
STUDYFLOW_POSTGRES_DB=studyflow
STUDYFLOW_POSTGRES_USER=studyflow_app
STUDYFLOW_POSTGRES_PASSWORD=GENERATED_BY_BOOTSTRAP_SCRIPT
STUDYFLOW_DATABASE_URL=GENERATED_BY_BOOTSTRAP_SCRIPT
STUDYFLOW_TOKEN_SIGNING_KEY=GENERATED_BY_BOOTSTRAP_SCRIPT
STUDYFLOW_API_HOST=api.example.com
STUDYFLOW_BACKUP_PASSPHRASE=GENERATED_BY_BOOTSTRAP_SCRIPT
STUDYFLOW_BACKUP_DIR=/var/backups/studyflow
```

`.env.example` 只用于说明变量，不能直接作为生产配置。新增 `bootstrap-env.sh`，在 VPS 的 `infra/` 目录执行 `./bootstrap-env.sh api.example.com`：脚本检查 `.env` 不存在后生成数据库密码和 JWT 密钥，构造已经填好密码的 `postgresql://...` URL，以 `600` 权限写入 `.env`，不输出数据库密码或 JWT 密钥；如果没有预先提供备份口令，脚本生成后只显示一次并要求立即保存到 VPS 之外的密码管理器。

- [ ] **Step 2: 更新启动和迁移行为**

保持 `infra/api.Dockerfile` 中 API 容器启动前执行 `alembic upgrade head`；Compose 启动顺序必须为 PostgreSQL 健康后再启动 API；`infra/Caddyfile` 只反代 API，PostgreSQL 不发布宿主机端口。

- [ ] **Step 3: 更新备份恢复脚本**

备份目标改为 Compose 网络中的本地 PostgreSQL；恢复检查必须支持临时 PostgreSQL 目标，并继续验证 AES-256-CBC/PBKDF2 产物的摘要。

- [ ] **Step 4: 更新中文部署文档**

文档按以下顺序编写：创建 VPS 用户、安装 Docker、在 `infra/` 执行 `./bootstrap-env.sh api.example.com`、启动 PostgreSQL/API/Caddy、执行健康检查、创建第一个邮箱账户、配置客户端、执行备份。不写任何真实公网 IP、数据库密码、JWT 密钥或 AI Key。Cloudflare 只需要添加 `api` 的 A 记录指向“阿里云服务器概览中显示的公网 IPv4”；先验证 Caddy 源站 HTTPS，再按需要启用代理并使用 Full (strict)，不要把数据库端口加入 DNS 或公网防火墙。

- [ ] **Step 5: 运行部署配置检查**

```bash
cd server
mise exec -- poetry run pytest tests/test_db_config.py tests/test_migration_config.py
cd ../..
docker compose --env-file infra/.env -f infra/docker-compose.yml config
```

Expected：Compose 配置展开成功，PostgreSQL 没有公网端口，环境示例不包含 Supabase 连接信息。

- [ ] **Step 6: Commit**

```bash
git add infra README.md tests/integration/test_deployed_health.py
git commit -m "docs: simplify local PostgreSQL deployment"
```

### Task 10: 集成验证与 macOS/Android 首轮验收

**Files:**

- Modify: `tests/integration/test_end_to_end_sync.py`
- Modify: `tests/integration/test_deployed_health.py`
- Modify: `tests/device/macos-matrix.md`
- Modify: `tests/device/android-originos6-matrix.md`
- Modify: `README.md`

**Interfaces:**

- 用户可以在 macOS 创建账户，在 iQOO Z9 Turbo 登录同一邮箱，并看到同步后的任务。
- 同一账户的 AI Key 不跨设备上传；每台设备单独配置即可。

- [ ] **Step 1: 运行服务端完整测试**

```bash
cd server
mise exec -- poetry run pytest -q
```

Expected：服务端认证、数据库、同步和健康检查通过；服务端不再加载 AI provider 或 AI API 路由。

- [ ] **Step 2: 运行 Flutter 完整测试**

```bash
cd apps/client
bash ../../tool/flutter test
```

Expected：客户端测试通过，未出现未处理的旧认证类型引用。

- [ ] **Step 3: 启动本地集成环境**

```bash
docker compose --env-file infra/.env -f infra/docker-compose.yml up -d --build
curl -fsS https://api.example.com/health/live
curl -fsS https://api.example.com/health/ready
```

Expected：两个健康接口均返回 `status=ok`；API 日志没有数据库连接错误。

- [ ] **Step 4: 验证账户链路**

在 macOS 客户端使用：

```bash
bash ../../tool/flutter run -d macos \
  --dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com
```

完成注册、退出、重新登录；确认 VPS API 日志出现 `/v1/auth/register` 和 `/v1/auth/login`，不再出现 `/v1/auth/bootstrap`。

- [ ] **Step 5: 验证跨设备同步**

在 macOS 创建任务并同步；在 OriginOS 6 客户端使用相同邮箱登录；执行同步并确认任务出现。再在 Android 修改任务，返回 macOS 验证冲突和更新行为。

- [ ] **Step 6: 验证 AI 配置隔离**

在 macOS 设置 AI Base URL、Model 和 API Key，完成连接测试；检查 VPS 数据库、API 日志和客户端普通日志均不包含 API Key；在 Android 上确认需要单独填写自己的 Key。

- [ ] **Step 7: 单独记录 TLS 问题**

同时运行 OpenSSL、Flutter 和服务端 tcpdump，只记录结果，不修改认证代码。OpenSSL 成功但 Flutter 失败时，将问题归档为 macOS 网络/TLS 客户端问题，不能以“认证接口错误”结案。

- [ ] **Step 8: 锁定客户端交付范围**

验证仓库只有 Flutter 作为主客户端；不存在 React Native、Tauri 或 Rust 主窗口工程。Windows、Linux 和 iOS 只沿用 Flutter 工程预留的目标，平台级接管能力通过已有 `platform_contract` 增加实现。本轮不要求用户编辑 Swift/Kotlin；macOS 只在 Xcode 中配置 Team、Automatically manage signing 和 entitlements，代码仍然写在 Dart 的 `apps/client/lib/`。

- [ ] **Step 9: Commit**

```bash
git add tests README.md
git commit -m "test: verify local email account and cross-device sync"
```

## 完成标准

- 新用户只需要邮箱和密码即可注册，不接触 VPS `.env`。
- 同一邮箱可在 macOS 和 OriginOS 6 登录，不需要 Pair 或 Recovery key。
- VPS 仅运行 Caddy、FastAPI 和 PostgreSQL，数据库不暴露公网端口。
- 所有同步数据均按 JWT 用户身份隔离。
- AI Base URL、Model 和 API Key 在设置页可配置；API Key 不上传、不入库、不进日志。
- Supabase 相关运行时变量、代码路径和部署步骤全部移除。
- 如果有需要保留的旧 Supabase 数据，已有独立加密归档；如果没有需要保留的数据，已明确记录不迁移；新版部署不隐式删除旧备份。
- 服务端和客户端测试通过，且部署文档不包含真实 IP 或秘密值。

## 明确不在本次计划内

- 邮箱验证码、邮件验证、邮件找回密码。
- 端到端加密和恢复密钥恢复。
- 服务器后台持有 AI API Key 并执行定时 AI 任务。
- iOS、Windows、Linux 的平台级接管能力。
- 自动把旧版加密同步数据转换成新版明文 JSONB 数据。
