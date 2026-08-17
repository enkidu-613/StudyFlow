# StudyFlow 项目代理说明

处理本项目的计划、开发、配置、认证、数据库、AI、跨平台客户端、VPS 部署和故障排查时，必须先读取：

`.agent/skills/studyflow-project-guidance/SKILL.md`

该 skill 是工程流程与用户沟通的权威规范；其中的模板位于：

`.agent/skills/studyflow-project-guidance/references/user-friendly-output-template.md`

核心要求：命令标明执行位置和身份；每个环境变量说明作用、来源、填写位置、敏感性和验证方式；部署步骤给出预期输出、故障证据、回滚和最终检查。不得在文档中写入真实 IP、密码、token、API key、私钥或恢复密钥。

## 工程上下文（给代理的注意事项）

以下内容面向开发代理与协作工具，普通用户请阅读根目录 `README.md`。

### 工具链

- 运行时版本由 mise 锁定：`python = "3.12.13"`、`flutter = "3.44.9"`（见 `mise.toml`）。
- 安装：`mise install`；Python 依赖管理用 Poetry：
  `mise exec -- poetry install`。
- 本机 macOS 环境可能保护系统 Flutter 目录；若 `flutter` 命令不可写，
  设置 `STUDYFLOW_FLUTTER_ROOT` 指向可写 SDK 副本（如 `$PWD/.tool-cache/flutter-sdk`）。
  `tool/flutter` wrapper 会禁用 Flutter 统计上报并重定向 `PUB_CACHE` 到已忽略的
  `.tool-cache/` 目录。
- 执行客户端命令一律走 wrapper：`cd apps/client && bash ../../tool/flutter ...`。

### 测试

- 服务端：`cd server && mise exec -- poetry run pytest`（认证、同步、日程策略、数据库与部署配置）。
- 客户端：`cd apps/client && bash ../../tool/flutter test`。
- 真实 API 客户端：`bash ../../tool/flutter run --dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com`
  （API Base URL 是公开配置，不是秘密）。
- 设备验收矩阵：`tests/device/android-originos6-matrix.md`、`tests/device/macos-matrix.md`。

### 技术地图

| 层 | 本项目实际采用 | 负责什么 | 不负责什么 |
|---|---|---|---|
| 客户端 | Flutter（Dart、Riverpod、GoRouter、Drift/SQLite） | 页面、设备能力、本地安全存储（token/AI Key） | 不保存服务端密钥、不做数据库管理 |
| API | FastAPI（Pydantic v2、SQLAlchemy Async、PyJWT、Argon2id） | 邮箱认证、JSON 同步、日程策略 | 不保存 AI Key、不执行定时 AI 任务 |
| 数据库 | PostgreSQL 16（VPS Docker 内网，JSONB） | 用户、会话、任务、日程和同步数据 | 不存明文密码（仅 Argon2id 哈希） |
| 反向代理 | Caddy（Docker 内网，仅发布 80/443） | HTTPS、域名转发、自动证书 | 不负责业务认证 |
| DNS/CDN | Cloudflare | 域名解析、边缘加速 | 不负责数据库端口转发 |

### 已实现功能（接口契约速查）

- **认证**：`POST /v1/auth/register`、`login`、`refresh`、`logout`；Argon2id 哈希、
  轮换刷新令牌（数据库只存摘要）、短期访问 JWT（作用域 `user_id`）。
- **同步**：`POST /v1/sync/push` 与 `GET /v1/sync/pull`；JSONB 负载按 JWT
  `user_id` 隔离；幂等操作 ID、基于游标的拉取。
- **日程策略**：`POST /v1/schedule/proposals/validate`；锚定目标起床时间的
  睡眠窗口小幅调整建议，需用户确认；锁定块和休息区间不改变。
- **AI 设置**：完全在客户端侧（设置页配置 Base URL、模型、Key）；密钥存设备
  安全存储，服务端没有任何 AI 路由。
- **客户端本地存储**：Drift/SQLite，每账号一个 `studyflow-<account>.sqlite3`
  文件（见 `apps/client/lib/storage/`），业务数据以 JSON payload + 通用同步表
  结构存储，配合 `_PendingOperations` 表实现离线排队。

### 部署

- 完整流程（Debian 12、Docker、Caddy、Cloudflare、防火墙、加密备份）见
  `infra/README.md`。
- `infra/` 用 Docker Compose 运行 PostgreSQL 16 + FastAPI + Caddy；
  只有 Caddy 对外发布 80/443，应用容器端口不直接暴露公网。
- 在 VPS 的 `infra/` 执行 `./bootstrap-env.sh api.example.com` 生成 `.env`
  （数据库密码、JWT 密钥、备份口令）。
- 生产环境不要使用已停止维护的 Fedora 34 镜像。
- 排障按 DNS → TCP → TLS/Cloudflare → Caddy → API → 数据库 → 认证逐层定位；
  看到 Cloudflare 525 时检查源站监听、证书、代理模式与日志，不要把关闭代理
  或防火墙当作默认修复。
- 用户环境变量注意：客户端只接收公开的 `STUDYFLOW_API_BASE_URL`；数据库密码、
  JWT 密钥、AI Key 不进入客户端构建。
