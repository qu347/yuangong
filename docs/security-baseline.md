# 安全基线

## 密钥与配置

- `.env`、私钥、证书、keystore、`key.properties` 与生产域名不得提交。
- `.env.example` 只包含明确的开发值；生产环境缺少关键变量时必须拒绝启动。
- Android 本阶段不配置 Release 签名，Windows 不创建正式签名安装包。

## 认证与授权

- 原生客户端使用 SimpleJWT：Access Token 15 分钟、Refresh Token 7 天。
- Flutter 通过平台安全存储分别保存两种 Token；退出和刷新失败时清理，不写入普通配置或日志。
- Refresh rotation 与 SimpleJWT 官方 blacklist 已启用；旧 Refresh、logout、logout-all 和员工离职产生的已登记会话均可服务端吊销。
- Dio 只记录 path/type/status，不记录 Authorization、密码、Token 或完整响应。
- 所有目录 API 由后端 JWT + IsAuthenticated 保护；客户端隐藏按钮不构成权限控制。
- RBAC 使用 Django Group/model permissions；`employee` 只读，`hr_admin`/`system_admin` 可管理目录并查看审计。
- Employee 离职会停用关联 User 并 blacklist 其已登记 Refresh Token；恢复在职不会自动恢复账号。
- 本地 MVP 暂用既有 username 登录，正式工号/邮箱/AD/LDAP 身份源仍由 `OPEN_DECISIONS.md` 管理。
- blacklist 不会撤回已经签发的 Access Token；普通退出后 Access Token 最长仍可使用 15 分钟。离职账号因 `is_active=False` 会被认证层拒绝。
- blacklist 启用前签发且未登记的历史 Refresh Token 无法追溯，最长受原 7 天有效期约束。

## 数据与日志

- 不在日志中输出密码、Token、身份证、工资、完整响应或数据库连接信息。
- 测试只使用虚构数据。
- 错误响应只返回稳定错误码与用户安全消息，不返回堆栈。
- AuditEvent append-only；API/Admin 都不允许修改或删除，changes 仅接受目录安全字段，禁止 Token、密码、Authorization、secret 和数据库/Redis 凭据。
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
