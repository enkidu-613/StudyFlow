# 本地 PostgreSQL 迁移边界

> 本文件固化 Supabase → 本地 PostgreSQL 切换时的数据边界，避免重构过程
> 静默丢弃或隐式解密旧数据。

## 结论

- 新版部署使用 VPS Docker 内网 PostgreSQL，不再连接 Supabase。
- 旧版加密同步载荷（`payload_nonce` + `payload_ciphertext`）**不在本计划内**
  自动恢复为明文；它只作为加密备份保留。
- 是否需要保留旧 Supabase 数据，由部署者自行决定，并通过下面两种路径之一
  明确记录，二选一，不能含糊。

## 路径 A：不迁移旧数据（推荐）

若旧 Supabase 没有需要保留的业务数据：

1. 在部署记录中写明“本次不迁移旧数据”。
2. 新版本地 PostgreSQL 以干净 schema 启动。
3. 不执行旧 Supabase 的 `pg_dump`，不把旧 Supabase URL 写入新生产 `.env`。

## 路径 B：先归档再切换

若旧 Supabase 有需要保留的数据，切换前必须完成独立加密归档：

1. 在**当前 shell 会话**（不写入 `.env`）设置：
   - `OLD_DATABASE_URL`：标准 `postgresql://` 形式的旧 Supabase Session Pooler
     URL（不要使用 `postgresql+asyncpg://`，因为该前缀只对 SQLAlchemy 有效，
     PostgreSQL CLI 不接受）。
   - `STUDYFLOW_BACKUP_PASSPHRASE`：备份口令。
2. 执行备份与恢复检查：

   ```bash
   cd /home/studyflow/app/infra
   export STUDYFLOW_DATABASE_URL="$OLD_DATABASE_URL"
   ./backup/backup.sh
   backup_artifact="$(find /var/backups/studyflow -maxdepth 1 -type f \
     -name 'studyflow-*.gpg' -print | sort | tail -n 1)"
   test -n "$backup_artifact"
   ./backup/restore-check.sh "$backup_artifact"
   ```

   预期输出包含 `Decryption and digest verified`，且不打印数据库密码或口令。
3. 将产物复制到 VPS 之外保存。
4. 旧 Supabase URL 不写入新生产 `.env`；数据库连接配置由
   `infra/bootstrap-env.sh`（Task 9）生成。

## 脚本契约

- `infra/backup/backup.sh` 和 `infra/backup/restore-check.sh` 始终保持
  `pg_dump --dbname="$DATABASE_URL"` 的标准 `postgresql://` 输入约定。
- 脚本不校验或执行旧加密载荷的解密；解密旧载荷不在本计划范围内。
- 备份产物继续使用 AES-256-CBC + PBKDF2（盐内嵌在 OpenSSL 头），文件名携带
  UTC 时间戳和密文 SHA-256 摘要。

## 不允许的行为

- 不把 `postgresql+asyncpg://` URL 直接传给 `pg_dump`/`psql`。
- 不把旧 Supabase URL、数据库密码或备份口令写入 Git、`.env`、日志或截图。
- 不在部署或迁移流程中静默删除旧备份。
