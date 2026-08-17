# StudyFlow 本机闭环调试与家庭服务器迁移实施计划

> **执行约束：** 本计划只在当前会话内执行，不使用子代理；每一步都必须先给出执行位置、命令、预期输出和失败处理。

**目标：** 在新主机到货前，先用 Mac 完成 StudyFlow 的本地 API、PostgreSQL、macOS 客户端和 Android 调试闭环；主机到货后再把同一套服务迁移到家庭服务器。

**架构：** 本机以 Podman machine + Podman Compose 启动 PostgreSQL 和 FastAPI。API 只监听 Mac 的回环地址 `127.0.0.1:8000`，macOS 客户端通过 Dart define 连接它。Android 调试通过 `adb reverse` 把手机或模拟器的回环端口映射到 Mac，不把开发数据库暴露到局域网。家庭服务器阶段使用 Fedora 44、rootless Podman Quadlet、PostgreSQL 和 Cloudflare Tunnel；Tunnel 直接转发到服务器回环 API，不部署 Caddy。

**技术栈：** Flutter 3.44.9 / Dart 3.12.2、Python 3.12.13、FastAPI、SQLAlchemy、Alembic、PostgreSQL 16、Podman、Podman Compose、Quadlet、Cloudflare Tunnel。

## 全局约束

- 当前代码和当前测试结果优先于 OpenCode 会话中的历史结论；历史“已完成”不能替代本次验证。
- 本项目使用本地 PostgreSQL 和邮箱/密码账户，不恢复 Supabase 作为运行时依赖。
- 客户端只接收 `STUDYFLOW_API_BASE_URL`；数据库密码、JWT 签名密钥、备份口令不进入客户端、Git 或普通日志。
- 本机开发允许 `http://127.0.0.1:8000`；生产环境客户端只能使用 HTTPS。
- 项目文档、CI 和脚本以 Podman 为标准；macOS 使用 `podman compose`，Fedora 44 生产环境使用 `systemctl --user` 管理 Quadlet。
- 不把真实 IP、密码、JWT 密钥、备份口令、Cloudflare Tunnel token 或 AI key 写入文档和仓库。
- 保留当前工作区中已有的 `.opencode/`、`.agents/`、`.reasonix/` 和计划文件改动；本计划不清理、不回滚、不覆盖它们。
- 256GB SSD 只作为运行盘，不能作为唯一备份介质；备份必须复制到独立磁盘、NAS 或其他独立存储。

---

### 阶段 0：处理 OpenCode 会话中已经暴露的凭据

**目的：** 先消除历史会话带来的安全风险，再开始新机器部署。

**执行位置：** Cloudflare 控制台、StudyFlow 客户端设置、密码管理器；不是仓库终端。

- [ ] 在 Cloudflare Zero Trust 的 Tunnels 页面撤销旧 Tunnel token，并为新主机创建新 Tunnel；不复用 OpenCode 会话中的旧 token。
- [ ] 如果会话中的账户密码、备份口令或任何 AI key 仍在使用，逐项更换；新值只存入密码管理器或本机受保护配置，不粘贴进 Git、Issue 或普通聊天日志。
- [ ] 检查仓库和文档只包含占位域名、变量名和示例，不包含旧 VPS 公网地址。

**验证：** 旧 Tunnel token 无法再用于登录或连接；客户端 AI 设置中的 key 仍能通过设置页重新保存。

**失败处理：** 无法确认某个凭据是否泄露时，按已泄露处理并轮换；不要继续猜测旧凭据是否安全。

---

### 阶段 1：固定本机工具链基线

**文件：** `mise.toml`、`tool/flutter`、`README.md`。

**执行位置：** Mac，仓库根目录 `/Users/enkidu/Documents/ChatGPT/StudyFlow`。

- [ ] 安装项目声明的工具：

```bash
cd /Users/enkidu/Documents/ChatGPT/StudyFlow
mise install
mise exec -- poetry install
cd apps/client
bash ../../tool/flutter pub get
```

- [ ] 记录工具链结果：

```bash
cd /Users/enkidu/Documents/ChatGPT/StudyFlow
bash tool/flutter doctor -v
xcode-select -p
xcodebuild -version
xcrun simctl list runtimes
```

**当前已知结果：** Flutter 3.44.9、Dart 3.12.2、Xcode 26.6 已识别；Android SDK 尚未安装；Xcode 模拟器运行时列表尚未能被 Flutter 读取。

**预期：** Python、Poetry、Flutter 依赖安装成功；macOS 桌面目标可识别。

**失败处理：** 不修改 `mise.toml` 版本；如果 Android SDK 缺失，安装 Android Studio 的 SDK/Platform Tools/Build Tools 后重跑 `flutter doctor -v`。模拟器运行时异常时先用 macOS 桌面验证，不阻塞服务端联调。

---

### 阶段 2：在 Mac 启动本地 PostgreSQL 和 API

**文件：** `infra/bootstrap-env.sh`、`infra/compose.yml`、`infra/api.Dockerfile`、`infra/healthcheck.sh`。

**执行位置：** Mac，仓库的 `infra/` 目录。

- [x] 安装并启动 Podman machine；确认 Compose provider 可用：

```bash
podman machine start
podman info
podman compose version
```

- [ ] 只为本机生成 `infra/.env`，不复制生产环境的 `.env`：

```bash
cd /Users/enkidu/Documents/ChatGPT/StudyFlow/infra
if [ ! -e .env ]; then
  STUDYFLOW_BACKUP_PASSPHRASE="$(openssl rand -hex 24)" ./bootstrap-env.sh localhost
fi
chmod 600 .env
```

这里的 `localhost` 只标记本机开发配置；本机不申请公网证书，也不需要 Cloudflare。

- [x] 启动数据库和 API：

```bash
podman compose --env-file .env -f compose.yml up -d --build postgres api
podman compose --env-file .env -f compose.yml ps
./healthcheck.sh http://127.0.0.1:8000/health/live
curl -fsS http://127.0.0.1:8000/health/ready
```

**预期：** `postgres` healthy、`api` running/healthy，健康检查返回 `{"status":"ok"}`，readiness 返回数据库可用状态。API 容器会按照 `infra/api.Dockerfile` 自动执行 Alembic migration。

**失败处理：** 先看 `podman compose --env-file .env -f compose.yml logs --tail=200 postgres api`；修复原因后重启。只执行 `podman compose --env-file .env -f compose.yml down` 可以停止本机服务并保留卷；不要使用 `down -v`，除非明确要删除本机测试数据。

---

### 阶段 3：先验证 macOS 客户端真实 API 闭环

**文件：** `apps/client/lib/config/client_config.dart`、`apps/client/lib/auth/`、`apps/client/lib/sync/`、`apps/client/lib/features/`。

**执行位置：** Mac，`apps/client/` 目录；API 保持在阶段 2 运行。

- [ ] 启动 macOS 客户端：

```bash
cd /Users/enkidu/Documents/ChatGPT/StudyFlow/apps/client
bash ../../tool/flutter run -d macos \
  --dart-define=STUDYFLOW_API_BASE_URL=http://127.0.0.1:8000
```

- [ ] 使用专门的本地测试邮箱创建账户并登录；不要在测试记录中写真实密码。
- [ ] 依次验证：注册、退出、重新登录、错误密码、离线创建任务、恢复联网后的同步、重复日程、开始提醒、专注计时自动完成、设置页 AI Base URL/Model/Key 保存与清除、备份创建/列表/删除。
- [ ] 每项记录“通过/失败、复现步骤、客户端日志、API 日志”，不要记录 access token、refresh token、数据库 URL 或 AI key。

**预期：** macOS 客户端显示登录和主界面；本地账户数据能在服务端 PostgreSQL 中完成认证和同步。

**失败处理：** 客户端连接错误先确认 `curl http://127.0.0.1:8000/health/live`；认证错误看 API 容器日志；同步错误检查登录后的用户上下文和 API base URL。不要把本机地址改成旧 VPS 地址。

---

### 阶段 4：补齐 Android 本机调试

**文件：** `apps/client/` Android 工程和现有 `tests/device/android-originos6-matrix.md`。

**前置条件：** Android Studio 已安装 SDK、Platform Tools 和至少一个 API 级别；iQOO Z9 Turbo 已打开开发者选项和 USB 调试。

- [ ] 连接设备并确认：

```bash
adb devices
```

- [ ] 将 Android 设备的回环端口映射到 Mac API：

```bash
adb reverse tcp:8000 tcp:8000
```

- [ ] 用和 macOS 相同的本机地址启动 Android 客户端：

```bash
cd /Users/enkidu/Documents/ChatGPT/StudyFlow/apps/client
device_id="$(adb devices | awk '$2 == "device" {print $1; exit}')"
test -n "$device_id"
bash ../../tool/flutter run -d "$device_id" \
  --dart-define=STUDYFLOW_API_BASE_URL=http://127.0.0.1:8000
```

**预期：** Android 通过 USB reverse 访问 Mac 上的 API，不需要把 8000 端口开放到局域网；OriginOS 6 上可以完成登录、同步、通知权限和后台提醒测试。

**失败处理：** `adb devices` 无设备时检查 USB 调试授权；设备能识别但请求失败时重新执行 `adb reverse --remove-all` 和 `adb reverse tcp:8000 tcp:8000`；不要为了临时测试把 API 暴露到公网。

---

### 阶段 5：完成本机回归并处理非阻塞警告

**文件：** `server/tests/`、`apps/client/test/`、`apps/client/lib/storage/app_database.dart`、`tests/device/`。

- [ ] 在仓库根目录重新执行：

```bash
cd /Users/enkidu/Documents/ChatGPT/StudyFlow/server
mise exec -- poetry run pytest -q
cd ../apps/client
bash ../../tool/flutter analyze
bash ../../tool/flutter test
```

- [ ] 记录本次测试总数和跳过原因；不能只引用 OpenCode 会话中的旧数字。
- [ ] 修复 Flutter 测试中 `_AccountDatabase` 被同一 QueryExecutor 多次实例化的 Drift warning，优先检查测试清理和 `AccountScopedStore` 生命周期；修复后再次运行完整测试。
- [x] `infra/backup/backup.sh` 已使用 `podman ps`/`podman exec`；本机 PostgreSQL 已完成一次真实加密备份检查。
- [ ] 把人工验收结果写入现有设备矩阵，不在文档中记录秘密或真实公网地址。

**当前基线：** 服务端 `124 passed, 8 skipped`；客户端 `176` 项测试全部通过；静态分析通过。当前唯一已见的质量问题是 Drift warning，不是测试失败。

---

### 阶段 6：主机到货后的迁移顺序

**目标主机：** Intel Xeon E3-1246 v3、16GB RAM、256GB SSD、KNA H81 主板。该配置足够支撑个人使用的 StudyFlow：FastAPI、PostgreSQL、Cloudflare Tunnel 和定时备份可以同时运行；需要重点检查散热、网卡、SSD 健康、24/7 功耗和家庭网络稳定性。

- [ ] 安装 Fedora 44 Server，设置固定局域网地址或 DHCP 保留。
- [ ] 创建 `studyflow` 非 root 账户，使用 SSH key；root 只用于初始系统配置。
- [ ] 安装 Podman；把项目上传到 `/home/studyflow/app/StudyFlow`，使用 rootless Quadlet 运行 API 与 PostgreSQL。
- [ ] 在服务器 `infra/` 执行 `./bootstrap-env.sh api.enkiud.com` 生成 `.env`；只把 `.env` 留在服务器，权限设为 600。若到货时 Cloudflare 使用了不同的 API 域名，只替换这个命令的第一个参数。
- [ ] 首次只启动 PostgreSQL 和 API，验证服务器局域网地址上的健康检查；确认数据库、账户、同步和备份成功后，再创建新的 Cloudflare Tunnel。
- [ ] Cloudflare Tunnel 的 public hostname 直接转发到 `http://127.0.0.1:8000`；不开放公网 8000，不把家庭路由器 80/443 端口转发到服务器。需要远程 SSH 时使用局域网 VPN/安全入口，不把 SSH 直接暴露给全网。
- [ ] 新机器首次部署完成后执行一次加密备份，并把备份复制到独立存储；再做一次恢复演练。

**迁移验收：** 外部 HTTPS 健康检查、注册/登录、跨设备同步、通知/专注、AI 设置、备份创建和恢复均通过后，才把客户端的生产 `STUDYFLOW_API_BASE_URL` 切换到新主机域名。
