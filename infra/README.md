# StudyFlow 部署文档

本目录包含 StudyFlow API 的自托管部署文件，目标环境是 Debian 12 VPS。

部署结构如下：

- Caddy 负责 HTTPS 证书、TLS 终止和反向代理。
- FastAPI API 运行在 Docker 容器中，只在 Docker 内部网络暴露 8000 端口。
- PostgreSQL 16 运行在同一台 VPS 的 Docker 内网，不暴露公网端口。
- Cloudflare 负责域名解析和可选的代理加速。

## 文件说明

- docker-compose.yml：启动 PostgreSQL、API 和 Caddy。只有 Caddy 对外发布 80、443 端口。
- api.Dockerfile：构建 Python 3.12、Poetry 和 FastAPI API 镜像；容器启动前执行数据库迁移。
- Caddyfile：将域名请求转发到 API 容器，并自动申请 HTTPS 证书。
- bootstrap-env.sh：在 VPS 生成生产 .env、随机密钥和数据库连接配置。
- backup/backup.sh：使用 AES-256-CBC + PBKDF2 加密 pg_dump 备份文件。
- backup/restore-check.sh：校验备份摘要，并可将备份恢复到临时 PostgreSQL。
- .env.example：环境变量说明模板；生产 .env 由 bootstrap-env.sh 生成，不要手工复制。

## 一、准备 Debian 12 VPS

> 执行位置：`VPS`（SSH 会话） · 执行身份：`studyflow 普通用户` + `sudo`

使用 studyflow 账户通过 SSH 登录 VPS，不要使用 root 运行应用：

~~~bash
ssh studyflow-vps
cat /etc/os-release
whoami
sudo -v
~~~

> 本仓库文档统一使用 `docker-compose`（Debian 12 官方源的旧版命令）。
> 如果你的系统只安装了新版 `docker compose`（V2 插件），把文中所有
> `docker-compose` 换成 `docker compose`；先用 `docker compose version`
> 或 `docker-compose version` 检测实际可用命令。

安装 Docker、Compose、随机值生成工具、防火墙和文件同步工具：

~~~bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose openssl rsync ufw
sudo systemctl enable --now docker
sudo usermod -aG docker studyflow
exit
~~~

重新登录，使 docker 用户组权限生效：

~~~bash
ssh studyflow-vps
docker --version
docker-compose version
~~~

### 1.1 Docker Hub 网络受限时

如果构建时报 `registry-1.docker.io` 连接超时，先确认阿里云 ACR 控制台的
"镜像工具 → 镜像加速器"地址，并在 VPS 上配置 Docker。该地址属于你的阿里云
账号，不要写入 Git 仓库：

~~~bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{"registry-mirrors":["你的阿里云ACR镜像加速器地址"]}
EOF
sudo systemctl restart docker
~~~

## 二、将 Cloudflare 域名指向 VPS

> 执行位置：`本机 Mac`（dig） + `Cloudflare 控制台`（浏览器） · 执行身份：`普通用户`

假设你的域名是 example.com，API 使用 api.example.com。不要把端口号写进
域名，也不要在 DNS 记录中填写 https://。

### 2.1 确认域名已经由 Cloudflare 托管

1. 登录 Cloudflare 控制台。
2. 在首页选择你的域名。
3. 如果状态显示为 Active，说明 Cloudflare 已经接管 DNS，可以继续。
4. 如果状态不是 Active，打开 Overview，复制 Cloudflare 分配的两个
   Nameserver，然后到域名注册商后台替换原来的 Nameserver。

### 2.2 创建 API 的 A 记录

在 Cloudflare 控制台依次进入：选择域名 → DNS → Records → Add record。

填写：

~~~text
Type（类型）：A
Name（名称）：api
IPv4 address（IPv4 地址）：你的 VPS 公网 IPv4
TTL：Auto
Proxy status：先选择 DNS only（灰云）
~~~

VPS 公网 IPv4 在阿里云控制台"云服务器 ECS → 实例 → 概览"中查看。不要为
api 添加指向错误地址的 AAAA 记录；如果 VPS 没有可用 IPv6，应删除旧的 api
AAAA 记录，否则部分客户端可能优先走 IPv6 而连接失败。

### 2.3 检查域名解析

在 Mac 上执行：

~~~bash
dig +short api.example.com
~~~

灰云状态下，结果应包含你的 VPS 公网 IP。

### 2.4 先让 Caddy 申请 HTTPS 证书

确认 VPS 的 80、443 端口已经开放，并启动 Caddy（第四步创建 .env 后再执行）：

~~~bash
cd /home/studyflow/app/infra
docker-compose --env-file .env up -d --build
docker-compose --env-file .env logs --tail=100 caddy
~~~

日志中应能看到 Caddy 为 api.example.com 申请或加载证书。然后在 Mac 上验证：

~~~bash
curl -fsS https://api.example.com/health/live
~~~

如果证书申请失败，优先检查域名解析、VPS 防火墙和服务商安全组是否放行 80、443。

### 2.5 打开 Cloudflare 代理并设置 Full (strict)

证书验证成功后，把 api 的 A 记录 Proxy status 从 DNS only（灰云）切换为
Proxied（橙云）。然后进入 SSL/TLS → Overview → Encryption mode，选择
Full (strict)。

## 三、上传代码

> 执行位置：`本机 Mac` · 执行身份：`普通用户`

从完成开发的目录上传到 VPS：

~~~bash
ssh studyflow-vps 'mkdir -p /home/studyflow/app'

rsync -az \
  --exclude='.git' \
  --exclude='.dart_tool' \
  --exclude='build' \
  --exclude='.tool-cache' \
  /Users/enkidu/Documents/ChatGPT/StudyFlow/ \
  studyflow-vps:/home/studyflow/app/
~~~

## 四、生成服务器配置

> 执行位置：`VPS` · 执行身份：`studyflow 普通用户`

在 VPS 上执行（api.example.com 换成你的实际域名）：

~~~bash
cd /home/studyflow/app/infra
./bootstrap-env.sh api.example.com
~~~

脚本会：
- 检查 .env 不存在，否则拒绝覆盖。
- 自动生成数据库密码和 JWT 签名密钥，构造完整的连接 URL。
- 以权限 600 写入 .env，不打印数据库密码或 JWT 密钥。
- 若未预先设置 STUDYFLOW_BACKUP_PASSPHRASE，生成一个并只显示一次，
  请立即保存到 VPS 之外的密码管理器。

生成的 .env 变量（全部由 bootstrap-env.sh 生成，只有 API_HOST 由你传入）：

| 变量名 | 作用 | 谁生成/提供 | 在哪里获取或生成 | 应填写什么 | 作用范围 | 敏感？ | 怎么验证 |
|---|---|---|---|---|---|---|---|
| `STUDYFLOW_POSTGRES_DB` | PostgreSQL 数据库名 | bootstrap-env.sh | 脚本自动写入 .env | `studyflow` | Docker 内 postgres 容器 | 否 | `docker-compose ps` 显示 postgres healthy |
| `STUDYFLOW_POSTGRES_USER` | 数据库应用用户 | bootstrap-env.sh | 脚本自动写入 .env | `studyflow_app` | Docker 内 postgres 容器 | 否 | 同上 |
| `STUDYFLOW_POSTGRES_PASSWORD` | 数据库密码 | bootstrap-env.sh（openssl rand -hex 24） | 脚本自动写入 .env，不打印 | 已生成的十六进制值 | Docker 内 postgres 容器 | 是 | 不要 echo、不进入 Git |
| `STUDYFLOW_DATABASE_URL` | API 连接 PostgreSQL 的完整 URL | bootstrap-env.sh | 脚本自动写入 .env | `postgresql://studyflow_app:<密码>@postgres:5432/studyflow` | API 容器 | 是 | `/health/ready` 返回 `database: ok` |
| `STUDYFLOW_TOKEN_SIGNING_KEY` | JWT 签名密钥（至少 32 字节） | bootstrap-env.sh（openssl rand -hex 32） | 脚本自动写入 .env，不打印 | 已生成的十六进制值 | 仅 API 容器 | 是 | 注册登录后受保护接口返回 200 |
| `STUDYFLOW_API_HOST` | 公开 API 域名 | 你 | 部署文档第二节；Cloudflare A 记录指向 VPS | `api.example.com` | Caddy 容器 | 否（公开地址） | `curl https://api.example.com/health/live` |
| `STUDYFLOW_BACKUP_PASSPHRASE` | 备份加密口令 | 你（密码管理器）或脚本生成 | 脚本生成时只显示一次，立即保存到 VPS 之外 | 高强度随机口令 | 备份脚本（VPS 之外备份时用） | 是 | `restore-check.sh` 输出校验通过 |
| `STUDYFLOW_BACKUP_DIR` | 备份输出目录 | bootstrap-env.sh | 脚本自动写入 .env | `/var/backups/studyflow` | 备份脚本 | 否 | 备份后目录出现 `.gpg` 文件 |

密码都是十六进制（hex）字符，不含 URL 特殊字符，因此数据库 URL 无需额外编码；
若将来手动填写含 `@`、`:`、`/` 的密码，必须按 RFC 3986 做百分号编码后再拼进 URL。

## 五、检查配置并启动服务

> 执行位置：`VPS` · 执行身份：`studyflow 普通用户`（docker 组）

先检查 Compose 配置是否完整：

~~~bash
cd /home/studyflow/app/infra
docker-compose --env-file .env config
~~~

没有出现变量缺失或 YAML 错误后，再构建并启动：

~~~bash
docker-compose --env-file .env up -d --build
docker-compose --env-file .env ps
~~~

API 容器会等待 PostgreSQL 健康后再启动，然后按顺序执行 Alembic 迁移和
Uvicorn。查看日志：

~~~bash
docker-compose --env-file .env logs --tail=100 api
docker-compose --env-file .env logs --tail=100 postgres
docker-compose --env-file .env logs --tail=100 caddy
~~~

## 六、防火墙

> 执行位置：`VPS` · 执行身份：`sudo`

只开放 SSH、HTTP 和 HTTPS。SSH 最好只允许你的公网 IP：

~~~bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 你的公网IP to any port 22 proto tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
sudo ufw status verbose
~~~

确认可以通过 SSH 密钥重新登录后，再启用防火墙规则。不要开放 API 的 8000
端口或 PostgreSQL 的 5432 端口。

## 七、验证 API

> 执行位置：`本机 Mac`（curl） · 执行身份：`普通用户`

从 Mac 或其他外部设备执行：

~~~bash
curl -fsS https://api.example.com/health/live
curl -fsS https://api.example.com/health/ready
~~~

live 接口应返回 status 为 ok。ready 接口会检查本地 PostgreSQL 连接。

如果失败，按以下顺序排查：

1. Cloudflare A 记录是否指向正确的 VPS IP。
2. Cloudflare SSL/TLS 是否为 Full (strict)。
3. VPS 是否开放 80、443。
4. Caddy 日志是否成功申请证书。
5. API 日志中的数据库连接或迁移错误。
6. postgres 容器是否健康（docker-compose ps）。

## 八、创建第一个邮箱账户

> 执行位置：`本机 Mac`（curl）或客户端 · 执行身份：`普通用户`

注册接口是公开的，直接使用 curl 创建首个账户（或直接使用客户端注册）：

~~~bash
curl -fsS -X POST https://api.example.com/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","password":"你的密码"}'
~~~

密码要求：8–16 位，必须包含大写字母、小写字母、数字和 ASCII 特殊符号
（如 `!@#$%^&*`）；不能全为纯数字、不能包含空格、不能与注册邮箱相同。
响应包含 access_token 和 refresh_token。不要在文档、日志或仓库中保存密码。

## 九、启动客户端

> 执行位置：`本机 Mac` · 执行身份：`普通用户`

客户端只需要公开 API 地址，不需要数据库密码、JWT 密钥或 AI Key：

~~~bash
cd /Users/enkidu/Documents/ChatGPT/StudyFlow/apps/client
bash ../../tool/flutter run \
  --dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com
~~~

首次使用时选择 Create account 注册邮箱和密码。登录后可在"设置 → AI 设置"
中为当前设备填写 AI Base URL、模型和 API Key；API Key 只保存在设备安全
存储中，不上传 VPS。

## 十、备份与恢复检查

> 执行位置：`VPS` · 执行身份：`sudo`（需要读取 .env 中的口令）

执行加密备份：

~~~bash
export STUDYFLOW_BACKUP_PASSPHRASE='你的备份密码'
export STUDYFLOW_DATABASE_URL='postgresql://studyflow_app:数据库密码@127.0.0.1:5432/studyflow'
sudo -E /home/studyflow/app/infra/backup/backup.sh
~~~

生产环境更简单的方式是在 .env 已存在的前提下导出变量后执行：

~~~bash
set -a; source /home/studyflow/app/infra/.env; set +a
sudo -E /home/studyflow/app/infra/backup/backup.sh
unset STUDYFLOW_DATABASE_URL STUDYFLOW_BACKUP_PASSPHRASE
~~~

备份文件应复制到 VPS 以外的独立位置。恢复检查：

~~~bash
/home/studyflow/app/infra/backup/restore-check.sh \
  /var/backups/studyflow/studyflow-备份文件.gpg
~~~

不要把备份密码写入 Git、Docker 镜像或客户端。

## 网络结构

~~~text
Android / macOS 客户端
        │ HTTPS
        ▼
Cloudflare DNS（代理开启，SSL/TLS 为 Full strict）
        │ HTTPS
        ▼
Caddy（VPS，只有 80/443 对外开放）
        │
        ▼
api:8000（Docker 私有网络）
        │
        ▼
postgres:5432（Docker 私有网络，不暴露公网）
~~~

## 当前生产注意事项

- 生产目标是 Debian 12；不要使用已停止维护的 Fedora 34。
- 不要直接暴露 API 的 8000 端口或 PostgreSQL 的 5432 端口。
- 不要在日志中输出访问令牌、数据库密码、JWT 密钥或备份密码。
- AI API Key 只在客户端设置页配置，服务端不保存、不读取。
- 若需从旧 Supabase 保留数据，先按
  `docs/superpowers/specs/2026-08-12-local-postgres-migration-boundary.md`
  执行独立加密归档，旧 Supabase URL 不写入新生产 .env。

## 常见失败与排障

排障先收集证据，再改配置；按 DNS → TCP 端口 → TLS/Cloudflare → Caddy →
API → 数据库 → 认证的边界逐层定位。

| 症状 | 最可能原因 | 下一条证据命令 |
|---|---|---|
| `dig +short api.example.com` 无结果 | DNS 未生效或 Nameserver 未切换 | 检查 Cloudflare Overview 状态与注册商 Nameserver |
| 浏览器/curl 显示 525 | Cloudflare 到源站 TLS 握手失败 | `curl -v https://api.example.com/health/live`，检查 Caddy 日志与 SSL/TLS 模式 |
| Caddy 无法申请证书 | 80/443 未放行或域名解析未生效 | `sudo ufw status verbose`；`docker-compose logs caddy` |
| `/health/live` 超时 | 防火墙或安全组拦截 | `sudo ufw status verbose`；阿里云安全组检查 80/443 |
| `/health/ready` 返回 503 | API 连不上 postgres | `docker-compose logs api`；`docker-compose ps` 看 postgres 是否 healthy |
| 注册登录 500 | 数据库迁移未执行或 JWT 密钥缺失 | `docker-compose logs api`（应出现 alembic 输出）；确认 `.env` 有 TOKEN_SIGNING_KEY |
| 客户端登录提示"无法恢复上次会话" | 本机网络代理或 TLS 中断 | 用 `curl -fsS https://api.example.com/health/live` 对比；不要把网络代理问题当作认证问题 |

Cloudflare 525 表示 Cloudflare 边缘无法与源站完成 TLS 握手：先确认 Caddy
监听 443、证书有效（Full strict 需要有效证书）、代理模式设置正确；不要
把"关闭代理"或"关闭防火墙"当作默认修复。

## 回滚

- **配置回滚**：`docker-compose --env-file .env down` 停止服务；修改
  `.env` 后重新 `docker-compose --env-file .env up -d`。`.env` 被覆盖前
  先 `cp .env .env.bak-$(date +%s)`。
- **代码回滚**：VPS 上 `cd /home/studyflow/app && git checkout <上一个提交>`，
  重新 `docker-compose --env-file .env up -d --build`。
- **数据库回滚**：从 `STUDYFLOW_BACKUP_DIR` 中最近的 `.gpg` 备份解密恢复
  到临时 PostgreSQL，验证后再决定是否覆盖生产数据。迁移降级不自动执行。
- **密钥泄露处理**：若 `.env` 泄露，重新执行 `./bootstrap-env.sh`（先删除
  旧 `.env`）生成新密钥，并撤销受影响账户的 refresh token（重启服务后旧
  会话自动失效）。

## 部署收尾清单

- [ ] `git diff --check`、服务端测试（`pytest`）和客户端测试（`flutter test`）通过。
- [ ] VPS 上 `.env` 权限为 600，未进入 Git，未出现在日志。
- [ ] 三个容器（postgres/api/caddy）healthy，`/health/live` 与 `/health/ready` 正常。
- [ ] 新用户可注册、登录、退出和重新登录。
- [ ] 两台设备使用同一邮箱登录后任务/日程能同步；冲突策略已说明（字段级合并/冲突副本）。
- [ ] 客户端 AI 设置可以保存、测试和清除；API Key 在系统安全存储中，未上传。
- [ ] 域名、HTTPS、反向代理、云防火墙和 VPS 防火墙均有验证证据。
- [ ] 已说明数据库备份、恢复命令和最近一次恢复演练结果。
- [ ] macOS/Android 实机验收结果已按 `tests/device/*-matrix.md` 记录 Observed 列。
