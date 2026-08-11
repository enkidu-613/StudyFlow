# StudyFlow 部署文档

本目录包含 StudyFlow API 的自托管部署文件，目标环境是 Debian 12 VPS。

部署结构如下：

- Caddy 负责 HTTPS 证书、TLS 终止和反向代理。
- FastAPI API 运行在 Docker 容器中，只在 Docker 内部网络暴露 8000 端口。
- PostgreSQL 使用 Supabase，不在 VPS 上运行数据库。
- Cloudflare 负责域名解析和可选的代理加速。

## 文件说明

- docker-compose.yml：启动 API 和 Caddy。只有 Caddy 对外发布 80、443 端口。
- api.Dockerfile：构建 Python 3.12、Poetry 和 FastAPI API 镜像。
- Caddyfile：将域名请求转发到 API 容器，并自动申请 HTTPS 证书。
- healthcheck.sh：API 容器的健康检查脚本。
- backup/backup.sh：使用 AES-256-GCM 加密 pg_dump 备份文件。
- backup/restore-check.sh：校验备份摘要，并可将备份恢复到临时 PostgreSQL。
- .env.example：环境变量模板。复制为 .env 后填写真实值；不要提交 .env。

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

Debian 12 的官方软件源使用 docker-compose 命令；本项目的部署命令均按此
命令编写，不要把它替换成当前 VPS 软件源中不存在的 docker-compose-v2。

## 二、准备 Cloudflare 域名

在 Cloudflare 中添加一个 A 记录：

~~~text
主机名：api
目标：VPS 公网 IPv4 地址
代理：开启
~~~

例如，最终 API 域名为 api.example.com。

Cloudflare 的 SSL/TLS 模式设置为 Full (strict)。Caddy 会在 80、443
端口可访问后自动申请和续期 HTTPS 证书。

## 三、上传代码

当前已验证的代码提交为 7f3bc7f。若本地使用 worktree，请从完成开发的
worktree 上传，不要从尚未同步的旧 main 目录上传：

~~~bash
ssh studyflow-vps 'mkdir -p /home/studyflow/app'

rsync -az \
  --exclude='.git' \
  --exclude='.dart_tool' \
  --exclude='build' \
  --exclude='.tool-cache' \
  /Users/enkidu/Documents/ChatGPT/StudyFlow/.worktrees/studyflow-mvp/ \
  studyflow-vps:/home/studyflow/app/
~~~

如果没有 studyflow-vps SSH 别名，将命令中的 studyflow-vps 替换为：

~~~text
studyflow@你的VPS公网IP
~~~

## 四、创建并填写服务器配置

在 VPS 上执行：

~~~bash
cd /home/studyflow/app/infra
cp .env.example .env
chmod 600 .env
~~~

生成两个相互独立的服务器密钥：

~~~bash
openssl rand -hex 32
openssl rand -hex 32
~~~

编辑配置文件：

~~~bash
TERM=xterm-256color nano .env
~~~

如果 VPS 没有 nano，可以使用 vi：

~~~bash
vi .env
~~~

必须填写以下变量：

### STUDYFLOW_DATABASE_URL

填写 Supabase 的 Session Pooler PostgreSQL 连接地址，端口必须是 5432，
并带有 sslmode=require。例如：

~~~text
postgresql://studyflow_server.项目引用名:数据库密码@aws-0-区域.pooler.supabase.com:5432/postgres?sslmode=require
~~~

不要使用以下身份：

- postgres
- anon
- authenticated
- service_role
- Supabase Data API Key

建议在 Supabase 中使用独立的 studyflow_server 数据库登录角色，并确保
该角色不是 BYPASSRLS。API 启动时会自动执行 Alembic 数据库迁移。

### STUDYFLOW_TEST_DATABASE_URL

这是测试数据库地址，只用于集成测试，不要指向生产 Supabase 数据库。
Docker 生产服务不会使用它，但建议保留配置：

~~~text
postgresql://studyflow_test:密码@127.0.0.1:5432/studyflow_test
~~~

### STUDYFLOW_BOOTSTRAP_TOKEN

填写第一个 openssl rand -hex 32 生成的值。

这是第一次初始化 StudyFlow 主账户时使用的一次性服务器令牌。它只在
客户端 Initialize/初始化表单中输入一次，不要放入客户端源码、Dart define
或 Git 仓库。

### STUDYFLOW_TOKEN_SIGNING_KEY

填写第二个 openssl rand -hex 32 生成的值。它用于签名访问令牌，不能与
STUDYFLOW_BOOTSTRAP_TOKEN 相同。

### STUDYFLOW_API_HOST

只填写域名，不要填写协议或路径：

~~~text
STUDYFLOW_API_HOST=api.example.com
~~~

### STUDYFLOW_BACKUP_PASSPHRASE

填写单独的高强度备份密码，不要复用数据库密码或认证密钥。

### STUDYFLOW_BACKUP_DIR

默认填写：

~~~text
STUDYFLOW_BACKUP_DIR=/var/backups/studyflow
~~~

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

API 容器启动时会按顺序执行数据库迁移和 Uvicorn。查看日志：

~~~bash
docker-compose --env-file .env logs --tail=100 api
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

确认可以通过 SSH 密钥重新登录后，再启用防火墙规则，避免误锁 VPS。
不要开放 API 容器的 8000 端口。

## 七、验证 API

从 Mac 或其他外部设备执行：

~~~bash
curl -fsS https://api.example.com/health/live
curl -fsS https://api.example.com/health/ready
~~~

live 接口应返回 status 为 ok。ready 接口会检查 Supabase 数据库连接。

如果失败，按以下顺序排查：

1. Cloudflare A 记录是否指向正确的 VPS IP。
2. Cloudflare SSL/TLS 是否为 Full (strict)。
3. VPS 是否开放 80、443。
4. Caddy 日志是否成功申请证书。
5. API 日志中的 Supabase 连接或数据库迁移错误。
6. STUDYFLOW_DATABASE_URL 是否使用 5432 的 Session Pooler。

## 八、启动客户端

客户端只需要公开 API 地址，不需要数据库密码、Supabase service key 或
服务器签名密钥：

~~~bash
cd /Users/enkidu/Documents/ChatGPT/StudyFlow/apps/client
bash ../../tool/flutter run \
  --dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com
~~~

首次使用时：

1. 选择 Initialize/初始化。
2. 输入 .env 中的 STUDYFLOW_BOOTSTRAP_TOKEN。
3. 设置至少 12 个字符的账户密码。
4. 进入 Settings/设置页，导出并离线保存恢复密钥。

其他设备使用 Pair/配对，通过主设备生成的六位配对码加入账户。

## 九、备份与恢复检查

执行加密备份：

~~~bash
export STUDYFLOW_BACKUP_PASSPHRASE='你的备份密码'
export STUDYFLOW_DATABASE_URL='postgresql://...pooler.supabase.com:5432/postgres?sslmode=require'
sudo -E /home/studyflow/app/infra/backup/backup.sh
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
Supabase PostgreSQL（Session Pooler，5432）
~~~

## 当前生产注意事项

- 生产目标是 Debian 12；不要使用已停止维护的 Fedora 34。
- 不要直接暴露 API 的 8000 端口。
- 不要在日志中输出访问令牌、数据库密码、bootstrap token 或备份密码。
- 当前代码中的 AI Provider 仍未配置真实模型密钥；部署 API 不会自动启用
  外部 AI 服务。
- Android OriginOS 6、macOS 原生权限和电脑接管能力仍需在真实设备上单独
  验收。
