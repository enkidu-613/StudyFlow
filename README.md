# StudyFlow

[English](README.en.md) | **中文**

StudyFlow 是一个跨平台学习助手：围绕固定的睡眠窗口规划一天，通过专注
计时帮助完成任务，并且**离线也能用**——恢复网络后自动同步。

## 特性

- **离线优先**：任务、日程、专注记录都存本地（Drift/SQLite），网络恢复后
  自动同步，无需担心断网。
- **日程策略**：以目标起床时间为锚点，提出小幅、可确认的睡眠窗口调整建议，
  锁定块与休息时间保持不变。
- **专注计时**：目标时长取自任务的预估分钟，倒计时结束自动完成并响铃提醒。
- **隐私优先的 AI 设置**：每台设备在设置页自行配置 AI 地址、模型与密钥，
  密钥只存在设备上，服务端不接触。
- **安全的邮箱认证**：Argon2id 密码哈希 + 短期访问令牌 + 轮换刷新令牌。

## 平台

| 平台 | 状态 |
|---|---|
| Android（iQOO Z9 Turbo / OriginOS 6） | ✅ 首批目标 |
| macOS | ✅ 首批目标 |
| Windows / Linux / iOS | 可通过平台契约后续支持 |

## 技术栈

- 客户端：Flutter（Dart、Riverpod、GoRouter、Drift/SQLite）
- 后端：FastAPI（Pydantic v2、SQLAlchemy Async、PyJWT、Argon2id）
- 数据库：PostgreSQL 16（JSONB）
- 部署：Docker Compose + Caddy + Cloudflare

## 快速开始

```bash
# 安装锁定版本的运行时
mise install

# 后端依赖
mise exec -- poetry install

# 客户端依赖
bash tool/flutter pub get
```

Android 构建会自动选择 Android Gradle 兼容的标准 JDK：优先使用由
`mise` 选中的标准 JDK，macOS 没有时使用已安装的 Homebrew OpenJDK；不会使用
GraalVM 或 Java 26。直接运行 Gradle 时也使用项目脚本：

```bash
# 项目根目录
bash tool/gradle :app:assembleDebug
```

如需临时指定 JDK，在命令前设置 `STUDYFLOW_JAVA_HOME`，值必须是包含
`bin/java` 和 `bin/jlink` 的 JDK 根目录。

## 测试

```bash
# 服务端（认证、同步、日程策略等）
cd server && mise exec -- poetry run pytest

# 客户端
cd apps/client && bash ../../tool/flutter test

# 连接真实 API 运行（API 地址是公开配置，不是秘密）
cd apps/client && bash ../../tool/flutter run \
  --dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com
```

## 目录结构

```
apps/client/    Flutter 客户端（功能按 features/ 拆分）
server/         FastAPI 后端（认证、同步、日程策略）
infra/          Docker Compose、Caddy、Cloudflare 部署与加密备份
packages/       共享领域包（domain 模型等）
tests/device/   设备验收矩阵（Android / macOS）
```

## 文档

- 部署与运维：`infra/README.md`
- 工程规范（面向开发代理与协作工具）：`.agent/AGENTS.md`
- 验收矩阵：`tests/device/android-originos6-matrix.md`、`tests/device/macos-matrix.md`

## 许可

设计与计划文档记录了我们参考学习的成熟开源项目（Super Productivity、
ActivityWatch、Vikunja、Nextcloud Calendar）；这些项目的代码没有被引入，
CalDAV 互操作推迟到后续计划。
