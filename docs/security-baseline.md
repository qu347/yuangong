# 安全基线

## 密钥与配置

- `.env`、私钥、证书、keystore、`key.properties` 与生产域名不得提交。
- `.env.example` 只提供变量名称和生成提示；production 缺少 Django/JWT、数据库、Redis、SMTP、账号 Token keyring 或审计归档 keyring 时必须拒绝启动。
- Django `SECRET_KEY`、JWT signing key、账号一次性 Token HMAC keyring 与审计归档 HMAC keyring 必须互相独立。
- Android Release 必须显式提供四个签名环境变量；ValidationOnly 只使用执行期间的一次性证书。Windows 无正式 PFX 时只生成 `UNSIGNED / NON-DISTRIBUTABLE` ZIP。

## 认证与授权

- 原生客户端使用 SimpleJWT：Access Token 15 分钟、Refresh Token 7 天。
- Flutter 通过平台安全存储分别保存两种 Token；退出和刷新失败时清理，不写入普通配置或日志。
- Refresh rotation 与 SimpleJWT 官方 blacklist 已启用；Access/Refresh 均包含同一 `sid`，并绑定服务端 `AccountSession`。
- 每个受保护请求使用 `SessionJWTAuthentication` 检查账号和会话；会话撤销、密码修改/重置、账号停用和角色变更会让旧 Access 与 Refresh 立即失败。
- Dio 只记录 path/type/status，不记录 Authorization、密码、Token 或完整响应。
- 所有目录 API 由后端 JWT + IsAuthenticated 保护；客户端隐藏按钮不构成权限控制。
- RBAC 使用 Django Group/model permissions；`employee` 只读，`hr_admin`/`system_admin` 可管理目录并查看审计；只有 `system_admin` 拥有 `audit.export_auditevent`。
- Employee 离职会停用关联 User 并 blacklist 其已登记 Refresh Token；恢复在职不会自动恢复账号。
- 登录接受稳定 username 或规范化账号邮箱，不接受工号别名。`User.email` 与 `Employee.work_email` 不自动双向同步。
- 缺少 `sid` 的旧 Access/Refresh 在第三阶段部署后统一拒绝，用户必须重新登录。
- 邀请和密码重置原始码不入库、不进 API/日志/审计；摘要按用途隔离。重置请求始终返回相同 202，避免账号枚举。
- system_admin 才能管理邀请和普通账号；业务 API 不授予 system_admin、不管理超级用户，也不允许停用当前账号。

## 数据与日志

- 不在日志中输出密码、Token、身份证、工资、完整响应或数据库连接信息。
- 测试只使用虚构数据。
- 本地邮件只发送到 `.invalid` 并由无持久卷 Mailpit 捕获；production 不默认启用 Mailpit。
- 错误响应只返回稳定错误码与用户安全消息，不返回堆栈。
- AuditEvent append-only；API/Admin 都不允许修改或删除，changes 仅接受目录安全字段，禁止 Token、密码、Authorization、secret 和数据库/Redis 凭据。
- CSV 导出固定字段、UTF-8 BOM/CRLF、最多 10000 行，并对 `= + - @ Tab CR LF` 前缀增加单引号；成功导出自身写入 `audit_exported`。
- 审计归档使用稳定 JSONL gzip、SHA-256 与 HMAC manifest。`AUDIT_RETENTION_DAYS=0` 表示无限期保留；本阶段没有 purge 命令或自动删除。
- 目录业务 API 和 Admin 均不提供物理删除；Employee 状态与账号关联在 Admin 中只读。

## 网络

- Staging 与 Production 只允许 HTTPS。
- Android cleartext HTTP 只由 `android/app/src/debug` 下的 manifest 与 Network Security Configuration 开启；Release 主清单不得引用该配置或全局允许明文流量。
- Debug HTTP 只用于受控本地开发联调；登录凭据和 Token 不得用于公共或不可信网络。
- `0.0.0.0:8000` 只用于可信开发局域网；应配置 Windows 防火墙并避免公共网络暴露。
- CORS 使用显式来源列表，不允许通配所有来源。

## 依赖与变更

- 依赖升级必须检查发布说明、安全公告与平台最低版本。
- 数据库修改必须有迁移，API 修改必须有测试与文档。
- CI 不使用生产密钥，不上传 APK 或安装包到外部服务。
- CodeQL 只覆盖 GitHub 官方支持的 Python，不声称覆盖 Dart；Dart 由格式、analyze 和 Flutter 测试覆盖。
- `scripts/repository-safety.ps1` 只是基础防误提交门禁，不替代专业秘密扫描、依赖审计或人工审查。
