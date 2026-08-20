# Production 配置合同

本文件描述可验证的 production 配置边界，不代表已经完成公网或正式生产部署。所有实际值必须由授权的部署系统注入，不得写入 Git、命令历史或报告。

## 必填变量

production settings 要求以下类别全部显式配置：

- Django/JWT：`DJANGO_SECRET_KEY`、`JWT_SIGNING_KEY`、`DJANGO_ALLOWED_HOSTS`、`CORS_ALLOWED_ORIGINS`、`API_PUBLIC_BASE_URL`。
- PostgreSQL：`POSTGRES_DB`、`POSTGRES_USER`、`POSTGRES_PASSWORD`、`POSTGRES_HOST`、`POSTGRES_PORT`。
- Redis：`REDIS_URL`。
- SMTP：`EMAIL_HOST`、`EMAIL_PORT`、`EMAIL_HOST_USER`、`EMAIL_HOST_PASSWORD`、`EMAIL_USE_TLS`、`EMAIL_USE_SSL`、`EMAIL_TIMEOUT`、`DEFAULT_FROM_EMAIL`、`SERVER_EMAIL`。
- 账号 Token：`ACCOUNT_TOKEN_HMAC_ACTIVE_KID`、`ACCOUNT_TOKEN_HMAC_KEYS_JSON`。
- 审计归档：`AUDIT_ARCHIVE_HMAC_ACTIVE_KID`、`AUDIT_ARCHIVE_HMAC_KEYS_JSON`、`AUDIT_ARCHIVE_DIR`。

production 拒绝 SQLite、LocMem、Mailpit/localhost SMTP、HTTP API、通配 Host/CORS、TLS 与 SSL 同时开启、`.invalid` 发件地址、未知 active key ID，以及不同用途间复用密钥。

## 密钥轮换

- Django、JWT、账号一次性 Token 和审计归档使用四个独立密钥域。
- 新邀请/重置 Token 格式为 `<kid>.<random>`，数据库保存 `token_key_id` 与摘要，不保存原始值。
- 校验新 Token 时只选择指定 key ID，不遍历 keyring。旧 `token_key_id IS NULL` 行仅使用旧 `SECRET_KEY` 兼容；`account_token_key_report` 只输出安全计数。
- 轮换时先把新 key 加入 JSON 并设为 active，保留仍有有效 Token/归档的旧 key。确认安全报告归零和保留策略后，才能另行审批移除。
- 归档 manifest 不包含 HMAC key。删除旧归档 key 会使对应历史归档无法再次完成 HMAC 验证。

## SMTP

开发只使用 Mailpit，测试只使用 locmem；production 使用通用 SMTP 后端。`send_account_email_probe` 必须显式 `--confirm`，并且只有获得 staging SMTP 凭据和收件授权后才运行。本阶段没有发送 staging 或真实外部邮件。

## Docker

`deploy/docker-compose.production.example.yml` 是配置合同：Gunicorn、非 root UID 10001、不运行 `runserver`、不自动 migrate、PostgreSQL/Redis 不暴露宿主端口、无 Mailpit。内部 HTTP healthcheck 通过可信 `X-Forwarded-Proto: https` 头满足 `SECURE_SSL_REDIRECT`；真实入口仍必须终止 TLS 并覆盖/清理不可信代理头。

验证示例：

```powershell
.\backend\.venv\Scripts\python.exe .\backend\manage.py check `
  --deploy --settings=config.settings.production
docker compose -f .\deploy\docker-compose.production.example.yml config --quiet
```

命令前必须只在当前进程注入安全值，结束后清除。production 示例不执行迁移；正式部署需要独立、可回滚的迁移步骤和备份验证。

## 发布边界

`config/release.validation.json` 使用 `https://validation.invalid`，只允许生成 `NON-DISTRIBUTABLE` 验证构建。正式发布必须先解决 `docs/OPEN_DECISIONS.md` 中的身份、域名、签名、SMTP、仓库治理和分发渠道事项。
