# StudyFlow 部署与本机联调（Podman）

本项目不使用 Docker daemon：macOS 用 `podman machine` + Compose 联调；未来的
Fedora 44 家庭服务器用普通用户运行的 Podman Quadlet 常驻服务。PostgreSQL 和 API
不会暴露到公网。

```text
Flutter 客户端 → HTTPS → Cloudflare Tunnel → 127.0.0.1:8000 API → Podman 私有网络 → PostgreSQL 16
```

Cloudflare 负责外部 HTTPS。Tunnel 的上游始终是 `http://127.0.0.1:8000`，所以
不需要 Caddy、不需要开放 80/443，也不需要路由器端口映射。

## 文件与变量

| 文件/变量 | 谁使用 | 敏感 | 用途/来源 |
|---|---|---:|---|
| `compose.yml` | macOS 本机 | 否 | 本机启动 API 与 PostgreSQL |
| `quadlet/` | Fedora 44 | 否 | rootless 常驻服务单元 |
| `.env` | API、PostgreSQL、备份 | 是 | `bootstrap-env.sh` 自动生成，权限 600 |
| `STUDYFLOW_POSTGRES_*` / `POSTGRES_*` | API / PostgreSQL | 密码项是 | 同一组数据库名称、用户、密码；后者供官方镜像初始化 |
| `STUDYFLOW_DATABASE_URL` | API、备份 | 是 | API 到 PostgreSQL 的连接 URL |
| `STUDYFLOW_TOKEN_SIGNING_KEY` | API | 是 | JWT 签名密钥 |
| `STUDYFLOW_API_HOST` | 文档、Tunnel | 否 | 公开域名，如 `api.example.com` |
| `STUDYFLOW_BACKUP_PASSPHRASE` | 备份/恢复 | 是 | 在密码管理器生成并保存的备份加密口令 |

`.env` 不进 Git。不要运行 `podman compose config`，它会把已展开的秘密打印到
终端；用 `podman compose ps` 和 `podman compose logs` 查看状态。

## 一、本机 macOS 联调

> 位置：Mac 终端 · 身份：当前 macOS 用户

```bash
brew install podman podman-compose
podman machine init --now
podman info --format 'rootless={{.Host.Security.Rootless}} cgroup={{.Host.Cgroups.Version}}'

cd /Users/enkidu/Documents/ChatGPT/StudyFlow/infra
STUDYFLOW_BACKUP_PASSPHRASE="$(openssl rand -hex 24)" ./bootstrap-env.sh localhost
chmod 600 .env
podman compose --env-file .env -f compose.yml up -d --build
podman compose --env-file .env -f compose.yml ps
curl -fsS http://127.0.0.1:8000/health/live
curl -fsS http://127.0.0.1:8000/health/ready
```

若 `.env` 已存在，说明已有本机配置；不要重建它，否则本地数据库/会话会失效。
预期 `ready` 返回 `"database":"ok"`。故障证据：

```bash
podman compose --env-file .env -f compose.yml logs --tail=100 postgres
podman compose --env-file .env -f compose.yml logs --tail=100 api
```

停止联调、但保留数据库卷和镜像：

```bash
podman compose --env-file .env -f compose.yml down
```

客户端只配置公开 API 地址，不传数据库、JWT 或 AI Key：

```bash
cd /Users/enkidu/Documents/ChatGPT/StudyFlow/apps/client
bash ../../tool/flutter run --dart-define=STUDYFLOW_API_BASE_URL=http://127.0.0.1:8000
```

Android USB 调试再执行 `adb reverse tcp:8000 tcp:8000`。AI Base URL、模型和
API Key 由用户在客户端“设置 → AI 设置”填写，仅保存在该设备安全存储中。

## 二、Fedora 44 家庭服务器准备

> 位置：Fedora 44 控制台/SSH · 身份：系统管理使用 `sudo`，应用使用 `studyflow`

```bash
sudo dnf upgrade -y
sudo dnf install -y podman openssl rsync git
sudo useradd --create-home --shell /bin/bash studyflow
sudo loginctl enable-linger studyflow
sudo install -d -m 700 -o studyflow -g studyflow /home/studyflow/.ssh
```

不要用 root 跑容器，也不需要 Docker 用户组；路由器不配置 80、443、8000 或
5432 的端口转发。

## 三、上传代码与生成服务器 `.env`

> 上传位置：Mac；服务器目录：`/home/studyflow/app/StudyFlow`

```bash
ssh studyflow@你的服务器局域网地址 'mkdir -p /home/studyflow/app/StudyFlow'
rsync -az --delete \
  --exclude='.git' --exclude='.dart_tool' --exclude='build' --exclude='.tool-cache' \
  --exclude='infra/.env' \
  /Users/enkidu/Documents/ChatGPT/StudyFlow/ \
  studyflow@你的服务器局域网地址:/home/studyflow/app/StudyFlow/
```

`--delete` 只删除服务器项目目录中已经不在本机仓库的文件；若其中有手工文件，先
移走。登录服务器后：

```bash
cd /home/studyflow/app/StudyFlow/infra
STUDYFLOW_BACKUP_PASSPHRASE='从密码管理器新建的高强度口令' \
  ./bootstrap-env.sh api.example.com
chmod 600 .env
```

只有两项需要你提供：`api.example.com`（公开 API 域名）和已经在密码管理器保存的
备份口令。数据库密码、完整数据库 URL、JWT 签名密钥全部由脚本生成，不能手填、
不能发送或提交到 Git。

## 四、启动 Fedora 44 的 rootless Quadlet 服务

> 位置：服务器 · 身份：`studyflow`

```bash
mkdir -p ~/.config/containers/systemd
cp /home/studyflow/app/StudyFlow/infra/quadlet/* ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start studyflow-postgres.service
systemctl --user start studyflow-api.service

systemctl --user status studyflow-postgres.service --no-pager
systemctl --user status studyflow-api.service --no-pager
podman ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
curl -fsS http://127.0.0.1:8000/health/live
curl -fsS http://127.0.0.1:8000/health/ready
```

API 必须只显示 `127.0.0.1:8000`；PostgreSQL 不应有主机端口。更新代码后的流程：
同步代码、复制 Quadlet 文件、再执行：

```bash
systemctl --user daemon-reload
systemctl --user restart studyflow-api.service
```

日志：

```bash
journalctl --user -u studyflow-api.service -n 100 --no-pager
journalctl --user -u studyflow-postgres.service -n 100 --no-pager
```

## 五、接入 Cloudflare Tunnel

> 位置：Cloudflare Zero Trust 控制台 + Fedora 44

创建 Tunnel 和公开 hostname：

| 配置项 | 值 |
|---|---|
| Public hostname | `api.example.com` |
| Service type | `HTTP` |
| URL | `http://127.0.0.1:8000` |

根据控制台为该 Tunnel 给出的步骤安装 `cloudflared`。Tunnel token 是
cloudflared 系统服务的配置，不写进本项目 `.env`。完成后从外部验证：

```bash
curl -fsS https://api.example.com/health/live
curl -fsS https://api.example.com/health/ready
```

## 六、防火墙、备份、排障与回滚

家庭网络不添加 Web 入站规则：不开放 80、443、8000、5432；SSH 仅在确有远程管理
需求时开放并限制来源。Fedora firewalld 检查命令：

```bash
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --list-all
```

备份（宿主机没有 `pg_dump` 时会自动用 Podman 容器内工具）：

```bash
cd /home/studyflow/app/StudyFlow/infra
set -a; . ./.env; set +a
mkdir -p "$HOME/studyflow-backups"
export STUDYFLOW_BACKUP_DIR="$HOME/studyflow-backups"
./backup/backup.sh
unset STUDYFLOW_DATABASE_URL STUDYFLOW_BACKUP_PASSPHRASE
```

把 `.gpg` 文件复制到另一台机器或对象存储。恢复检查：

```bash
/home/studyflow/app/StudyFlow/infra/backup/restore-check.sh \
  "$HOME/studyflow-backups/你的备份文件.gpg"
```

排障顺序：先 `curl http://127.0.0.1:8000/health/ready`，再看 API/PostgreSQL
日志，最后检查 Tunnel hostname 是否指向 `http://127.0.0.1:8000`。停止回滚：

```bash
systemctl --user stop studyflow-api.service studyflow-postgres.service
```

代码回退后同步代码、复制 Quadlet 文件并执行 `systemctl --user daemon-reload` 与
`systemctl --user restart studyflow-postgres.service studyflow-api.service`。数据库迁移不
自动降级；先完成加密备份与恢复演练。
