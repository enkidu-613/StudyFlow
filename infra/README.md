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

使用 studyflow 账户通过 SSH 登录 VPS，不要使用 root 运行应用：

~~~bash
ssh studyflow-vps
cat /etc/os-release
whoami
sudo -v
~~~

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

生成的 .env 变量：

| 变量名 | 作用 | 敏感？ |
|---|---|---|
| STUDYFLOW_POSTGRES_DB | 数据库名 | 否 |
| STUDYFLOW_POSTGRES_USER | 数据库应用用户 | 否 |
| STUDYFLOW_POSTGRES_PASSWORD | 数据库密码 | 是 |
| STUDYFLOW_DATABASE_URL | API 连接 PostgreSQL 的完整 URL | 是 |
| STUDYFLOW_TOKEN_SIGNING_KEY | JWT 签名密钥（至少 32 字节） | 是 |
| STUDYFLOW_API_HOST | 公开 API 域名 | 否 |
| STUDYFLOW_BACKUP_PASSPHRASE | 备份加密口令 | 是 |
| STUDYFLOW_BACKUP_DIR | 备份目录 | 否 |

## 五、检查配置并启动服务

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

注册接口是公开的，直接使用 curl 创建首个账户（或直接使用客户端注册）：

~~~bash
curl -fsS -X POST https://api.example.com/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","password":"你的至少12位密码"}'
~~~

响应包含 access_token 和 refresh_token。不要在文档、日志或仓库中保存密码。

## 九、启动客户端

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
