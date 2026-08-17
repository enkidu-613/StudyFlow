# StudyFlow Podman Runtime Migration Implementation Plan

> **执行方式：** 仅在当前会话内联执行，不使用子代理。当前工作区已有用户未提交改动；本计划只修改列出的容器相关文件。

**目标：** 让 StudyFlow 不再依赖 Docker 或 Docker 守护进程：Mac 使用 Podman machine + Podman Compose 做本地联调，Fedora 44 家庭服务器使用 rootless Podman Quadlet 作为开机自启的生产运行方式。

**架构：** `infra/compose.yml` 是本机开发的中立 Compose 定义，由 `podman compose` 运行。生产环境由 `infra/quadlet/` 中的 rootless Quadlet 文件创建 PostgreSQL 卷、私有网络、API 镜像和 API/PostgreSQL 容器；Cloudflare Tunnel 直接连宿主机回环 API。备份脚本将 Podman 作为唯一容器回退运行时。

**技术栈：** Podman 6、podman-compose、Podman machine（macOS）、Quadlet/systemd user service（Fedora 44）、PostgreSQL 16、FastAPI、Cloudflare Tunnel。

## 全局约束

- 生产容器以 `studyflow` 普通用户 rootless 运行；不启用 Docker daemon，不创建 docker 用户组。
- 数据库和 API 不发布到公网；本机 API 只发布 `127.0.0.1:8000`。
- `.env` 继续仅保存在 `infra/.env`，权限 600；不写入 Git、日志或文档示例。
- 旧设计文档保留历史事实；只更新 README、infra README、实际部署文件和测试。
- Podman Compose 只用于本机开发；Fedora 44 生产启动、重启和日志由 `systemctl --user` 管理 Quadlet 生成的 unit。

---

### Task 1: 安装并验证本机 Podman

**Files:** 不修改仓库文件。

- [x] 安装 Podman 和 Compose provider：

```bash
brew install podman podman-compose
podman machine init --now
podman info
podman compose version
```

- [x] 验证本机镜像拉取和容器运行：

```bash
podman run --rm docker.io/library/alpine:3.22 echo podman-ready
```

**预期：** 命令输出 `podman-ready`；`podman info` 显示运行中的 machine。

---

### Task 2: 为 Podman 备份回退编写失败测试并实现

**Files:**
- Modify: `tests/integration/test_deployed_health.py`
- Modify: `infra/backup/backup.sh`

- [x] 添加集成测试：在临时 `PATH` 放置只实现 `podman ps`、`podman exec` 的假命令，隐藏 `pg_dump`，运行 `backup.sh` 后断言生成可解密的 `.gpg` 备份。
- [x] 单独运行该测试，确认它先因脚本调用 `docker` 而失败。
- [x] 将脚本的容器发现与 `pg_dump` 调用改为 `podman ps` 和 `podman exec`，并保留宿主机 `pg_dump` 优先级。

**预期：** 没有宿主机 `pg_dump` 时，脚本使用 Podman 中的 PostgreSQL 容器完成加密备份；备份口令和数据库 URL 不出现在输出中。

---

### Task 3: 使本机 Compose 配置成为 Podman 标准

**Files:**
- Rename: `infra/docker-compose.yml` to `infra/compose.yml`
- Modify: `tests/integration/test_deployed_health.py`
- Modify: `README.md`
- Modify: `infra/healthcheck.sh`

- [ ] 先修改测试 fixture，使其读取 `infra/compose.yml`；运行测试确认在重命名前失败。
- [x] 重命名配置文件，保留 PostgreSQL/API 的网络、健康检查、卷和回环 API 端口约束；删除不适合 rootless 生产路径的 Caddy。
- [x] 将用户可见的本机运行命令改为 `podman compose --env-file .env -f compose.yml`。
- [x] 用真实 `up`、`ps` 与健康检查验证配置（不运行会泄露 `.env` 的 `compose config`）。

**预期：** 本机 Podman Compose 可以创建 PostgreSQL 和 API；API 健康检查返回 `{"status":"ok"}`。

---

### Task 4: 添加 Fedora 44 rootless Quadlet 生产定义

**Files:**
- Create: `infra/quadlet/studyflow.network`
- Create: `infra/quadlet/studyflow-postgres.volume`
- Create: `infra/quadlet/studyflow-api.build`
- Create: `infra/quadlet/studyflow-postgres.container`
- Create: `infra/quadlet/studyflow-api.container`
- Modify: `infra/.env.example`
- Modify: `infra/README.md`

- [x] 定义私有网络、PostgreSQL 数据卷、API 构建和两个容器；所有 unit 使用 `.env`，API 只发布 `127.0.0.1:8000`，PostgreSQL 不发布端口。
- [x] 为 API/PostgreSQL 配置依赖、健康检查、restart 行为与 15 分钟启动超时。
- [x] 文档给出 Fedora 44 的 Podman 安装、rootless Quadlet 目录、`systemctl --user daemon-reload`、启动、状态、日志、`loginctl enable-linger studyflow`、Tunnel 与回滚命令。
- [x] 文档明确 Quadlet 是生成的 unit，使用 `systemctl --user start`，不使用 `enable`。

**预期：** 到货主机上无需 Docker、无需 root 容器；用户会话退出后仍可通过 linger 保持服务。

---

### Task 5: 完成本机 Podman 真实联调与回归

**Files:**
- Modify: `infra/README.md`
- Modify: `docs/superpowers/plans/2026-08-16-local-mac-debug-and-home-server.md`

- [x] 在本机生成一次仅本机使用的 `infra/.env`，启动 PostgreSQL/API。
- [x] 验证 `/health/live`、`/health/ready`、注册、登录和加密备份。
- [ ] 运行服务端 pytest、Flutter analyze、Flutter test；记录实际数量、跳过项和警告。
- [x] 将家庭服务器目标从 Debian 12/Docker 更新为 Fedora 44/Podman Quadlet，并保留 Cloudflare Tunnel 不直接暴露应用端口的边界。

**预期：** Podman 是仓库唯一推荐的容器运行时；测试与本机 API 健康检查通过；剩余的 Android SDK、真实手机和新主机验收明确标注为后续人工步骤。
