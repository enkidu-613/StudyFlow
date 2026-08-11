---
name: studyflow-project-guidance
description: Use when working in the StudyFlow repository on implementation plans, environment configuration, VPS deployment, database/auth setup, cross-platform clients, AI provider settings, or troubleshooting where the user needs copyable steps and an explanation of every variable, credential source, expected result, and rollback path.
---

# StudyFlow 项目指导

让用户能够理解、执行并验证 StudyFlow 的每一步。任何方案都必须回答：改什么、在哪执行、值从哪里来、成功长什么样、失败如何定位、是否可以回滚。

## 开始前读取上下文

先读取：

- `.agent/AGENTS.md` 和本文件。
- 当前计划、根目录 `README.md`、相关模块 README、`mise.toml`。
- 实际的 `server/`、`apps/client/`、`infra/` 文件和 `.env.example`。
- `git status --short`，区分用户已有修改、计划中的修改和本次修改。

不要把计划书当成已部署事实；先用文件、命令输出或日志确认当前状态。不要假设仍在使用 Supabase、某个数据库、某个域名或某个认证流程。

## 方案与实施契约

对每个阶段使用 [友好计划与部署模板](references/user-friendly-output-template.md)，至少写出：

1. 目标和完成后的可见结果。
2. 当前证据、前置条件和技术取舍。
3. 修改的文件及其职责。
4. 每条命令的执行位置：`本机 Mac`、`VPS`、`项目根目录`、`客户端目录`或`服务器目录`。
5. 可直接复制的命令、预期输出和验证命令。
6. 常见失败原因、对应日志和安全的回滚动作。
7. 阶段完成检查点；未通过检查点时不要静默进入下一阶段。

先完成一个最小可运行切片，再扩展功能。涉及数据库迁移、权限、防火墙、证书、删除数据或覆盖部署时，先写安全边界、备份和回滚路径；得到用户授权后再执行破坏性动作。

## 配置、账户与密钥

每个环境变量必须进入“变量说明表”，列出：变量名、作用、谁生成或提供、准确获取位置、填写示例、作用范围、是否敏感、验证方式。禁止只写 `[YOUR-PASSWORD]`、`填你的 token` 或一串没有来源的常量。

- 生成的服务端密钥使用明确命令，例如在 VPS 执行 `openssl rand -hex 32`，说明结果写入哪个 `.env` 项、只由哪个服务读取。
- 用户提供的 AI `BASE_URL`、模型名和 API key 说明“客户端设置页 → AI 设置”的具体字段；除非架构明确要求，否则不要塞进服务端 `.env`。
- 邮箱注册密码由用户在注册页创建；说明服务端如何哈希、数据库存什么、登录请求经过哪条链路。不要把普通登录密码当作 VPS 密码、数据库密码或 JWT 密钥。
- SSH、数据库、JWT、第三方 API key、恢复密钥分别解释来源和用途，不能混称为“token”。
- `.env`、私钥、恢复密钥和真实 IP 不写入 Git、计划书、截图或最终示例；使用 `api.example.com`、`<VPS_PUBLIC_IP>` 和 `<REDACTED>`。
- 数据库 URL 中的特殊字符必须说明 URL 编码规则；不要把未经编码的密码直接拼进连接串。
- 缺少真正需要用户提供的秘密时，只指出准确的文件、变量名、获取页面或生成命令；不要猜测，也不要索取已经可以在仓库或服务器上检查到的内容。

## 部署与排障

部署文档按“本机准备 → 推送 → VPS 登录 → 备份 → 安装/更新 → 写入 `.env` → 启动 → 迁移 → 健康检查 → 注册登录 → 同步 → AI → 备份恢复验证”排列。每一步都标注当前用户和目录。

同时检查云厂商安全组和 VPS 内防火墙；解释 22、80、443 或应用内部端口各自的用途，应用容器端口默认不直接暴露公网。兼容 `docker compose` 与旧版 `docker-compose` 时，先检测实际可用命令再给对应写法。

排障先收集证据，再改配置，按 DNS → TCP 端口 → TLS/Cloudflare → Caddy/反向代理 → API → 数据库 → 认证的边界逐层定位。看到 Cloudflare 525 时解释为边缘到源站 TLS 握手失败，分别检查源站监听、证书、代理模式和日志；不要把关闭代理、关闭防火墙或关闭用户网络代理当作默认修复。

## 交付标准

完成前必须实际运行与风险相称的测试、配置校验、健康检查和关键用户流程。最终报告用中文，先给结论，再列：已改文件、用户需要填写的最少项目、每项来源、验证结果、剩余风险和下一步。没有新证据就不要声称“已完成”“已部署”或“已修复”。
