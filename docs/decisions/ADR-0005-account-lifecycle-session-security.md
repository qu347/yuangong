# ADR-0005：账号生命周期、密码恢复与服务端会话安全

- 状态：Accepted
- 日期：2026-08-18
- 适用阶段：第三期账号安全与基础 CI
- 基线：`origin/main` 的 `d64b122`

## 背景

ADR-0003 建立了唯一 `accounts.User`、SimpleJWT 登录/刷新和 Flutter 单一认证基础设施；ADR-0004 增加 Django Group/model permissions、Refresh rotation/blacklist、目录写入和 append-only `AuditEvent`。现有系统仍缺少账号创建闭环、密码恢复、逐设备会话以及 Access Token 即时吊销。当前 logout 只能 blacklist Refresh，已签发 Access 最长仍可使用 15 分钟。

第三阶段必须复用现有 User、JWT、RBAC、审计、ApiClient、TokenStorage、AuthSessionStore 与 go_router，不建立平行身份体系。

## 范围

本阶段实现账号邀请与接受、初始密码、用户名/账号邮箱登录、忘记/重置/修改密码、账号启停、employee/hr_admin 角色调整、逐设备 AccountSession、JWT `sid`、Access 即时吊销、会话撤销、邮件抽象、开发 Mailpit、认证限流、Flutter 安全与账号管理页面，以及基础 GitHub Actions CI。

不实现 MFA、Passkey、短信、外部 SSO/LDAP、生产 SMTP、客户端深链、审计导出/归档、多租户、生产签名或发布。

## 既有账号限制

- `accounts.User` 是唯一用户模型，继续继承 `AbstractUser`。
- `username` 是内部稳定唯一标识，不改为工号或邮箱主键。
- 既有 `User.email` 可空、非唯一；迁移前审计为 1 个非空虚构邮箱、0 个大小写不敏感冲突。
- 现有 Token 没有 `sid`。部署第三阶段后，所有无 `sid` Token 统一 401 并要求重新登录，不保留兼容旁路。

## 登录标识与邮箱

登录请求首选 `identifier`，兼容旧 `username`；两者同时出现返回 400。identifier 先 trim：包含 `@` 时按 `User.email__iexact` 查找，否则按 username 精确查找，再交给 Django `authenticate()` 验证密码。所有不存在、inactive、重复或密码错误情况统一返回“登录名或密码错误”。

`User.email` 是账号登录、邀请和密码恢复邮箱；`Employee.work_email` 只是目录字段。邀请默认从 Employee.work_email 预填账号邮箱，接受后不自动双向同步。HR 修改目录邮箱不能改变账号身份；账号邮箱只能由 system_admin 通过账号 API 修改。

User 保存时把非空 email trim 并全小写。新增条件表达式唯一约束：空字符串可重复，非空 email 使用 `Lower(email)` 大小写不敏感唯一。迁移不自动合并冲突；存在冲突时停止。

## 密码策略

继续使用 Django `set_password()`、`check_password()` 和官方 validators。最小长度改为 12；保留常见密码和纯数字校验；新增 `AccountContextSimilarityValidator`，比较 username、email、Employee.full_name 和 employee_no。所有邀请接受、密码重置和修改密码都调用统一 `validate_account_password()`。

密码从不进入日志、响应、AuditEvent、缓存键或邮件以外的持久层。密码修改/重置成功后撤销全部会话，客户端清 Token，用户重新登录。

## 一次性安全 Token

邀请和密码重置使用 `secrets.token_urlsafe(32)` 生成原始一次性代码。数据库只保存以 `SECRET_KEY` 为 HMAC key、以用途字符串做域分离的 HMAC-SHA256 digest。比较使用 `hmac.compare_digest()`。原始代码只传给邮件服务，不返回普通 API、不写日志、不写审计。

## AccountInvitation

字段：UUID id、Employee FK、规范化 email、username、target_role、唯一 token_digest、expires_at、accepted_at、revoked_at、created_by SET_NULL、send_count、last_sent_at、created_at、updated_at。target_role 只允许 employee/hr_admin。

默认有效期 48 小时，由 `ACCOUNT_INVITATION_TTL` 配置。同一 Employee 只有一个未接受且未撤销邀请；创建新邀请前锁定 Employee 并把已过期的旧邀请标记 revoked。只允许 active、未绑定 User 的 Employee。username/email 必须未被 User 或有效邀请占用。

重发在事务中撤销旧 digest、生成新 digest、延长到期时间并发送新邮件；旧代码立即失效。撤销和重发幂等规则固定为：已接受返回 409，已撤销重复撤销返回 changed=false，已撤销邀请不能重发。

接受邀请是 anonymous 事务：按 digest 锁定邀请，统一拒绝过期/撤销/已接受；重新校验 Employee active 且无 User；创建 User、设置密码与 email、绑定 Employee、分配 target Group、标记 accepted，并记录 `account_invitation_accepted`。审计 actor 采用新创建 User；不自动签发 JWT。

## PasswordResetChallenge

字段：UUID id、User FK、唯一 token_digest、expires_at、used_at、revoked_at、requested_from 安全枚举、created_at。默认有效期 30 分钟，由 `PASSWORD_RESET_TTL` 配置。

忘记密码请求始终 202。只有 active、具有非空邮箱的唯一账号会在事务中撤销旧有效 challenge、创建新 challenge 并发邮件。不存在、inactive、无邮箱或受限流时都不暴露差异。确认按 digest 行锁，统一拒绝过期/撤销/已使用；验证新密码、`set_password()`、标记 used、撤销全部会话、审计 `password_reset_completed`，不激活、不登录。

## AccountSession 与 JWT sid

`AccountSession.id` 是 UUID `sid`。其余字段：User FK、created_at、last_seen_at、expires_at、client_platform、client_name、app_version、current_refresh_jti、revoked_at、revoked_reason。只存安全平台/客户端标签，不存 Token、Authorization、硬件标识、IP 或位置。

登录验证成功后在事务中创建 AccountSession，再签发同一 `sid` 的 Refresh/Access，保存当前 Refresh JTI。客户端元数据来自登录请求的受限字段：platform 仅 windows/android/unknown；client_name 最大 80；app_version 最大 32。

Refresh 必须携带 sid，且 Session 存在、属于 token user、active、未过期、current_refresh_jti 与旧 Refresh 一致。rotation 后新 Access/Refresh 保留 sid，旧 Refresh blacklist，Session 保存新 JTI。无 sid 或 JTI 不匹配统一失败。

## 即时 Access 吊销

DRF 默认认证类替换为 `SessionJWTAuthentication`，内部复用 SimpleJWT 签名/过期/User 检查，再验证 sid 对应 Session。Session 不存在、已撤销、已过期或 user 不匹配返回 401 `session_revoked`。公开端点不经过该认证。

正确性优先，每个受保护请求允许一次轻量 Session 查询。last_seen_at 只在距上次写入至少 5 分钟时用条件 UPDATE 更新，不引入 Redis 会话缓存。

logout 撤销当前 sid 并 blacklist 当前 Refresh；logout-all 撤销当前用户全部 Session；密码修改/重置、账号停用和角色变化同样撤销所有 Session。撤销后已有 Access 下一请求立即 401。

## 会话 API

- `GET /api/v1/auth/sessions/`
- `POST /api/v1/auth/sessions/{id}/revoke/`
- `POST /api/v1/auth/sessions/revoke-others/`

列表只返回当前用户的 id、平台、客户端名、版本、创建/最近活动/到期时间和 is_current；不返回 JTI/Token/IP。撤销只能作用于自己的 Session；跨用户 ID 返回 404。撤销当前 Session 后客户端退出；revoke-others 保留当前 sid并返回数量。

## 账号生命周期与角色

账号列表/详情、邀请管理、账号 PATCH、activate/deactivate/change-role/revoke-sessions 只允许 `can_manage_accounts` 的 system_admin。能力来自 Django permissions，不按用户名硬编码。

system_admin Group 新增 `accounts.view_user`、`accounts.change_user` 和 AccountInvitation 的 add/view/change；hr_admin 不获得这些权限。业务 API 不管理 superuser，也不管理 system_admin 角色账号；system_admin 账号仍只由 Django Admin 超级用户处理。

deactivate 不修改 Employee 状态，不能停用当前账号；它撤销全部会话并审计。activate 要求关联 Employee active、非空有效账号邮箱和受管角色；不恢复旧会话。change-role 只接受 employee/hr_admin，一个普通账号只保留一个受管主角色；保留无法确认来源的额外 permissions，但 UI capability 只来自受管权限。角色变化撤销全部会话。

## capabilities

保留第二阶段字段并新增：`can_manage_accounts`、`can_invite_accounts`、`can_manage_account_roles`、`can_view_sessions`、`can_revoke_other_sessions`、`can_change_password`。Flutter 缺失字段默认 false；后端仍是权威。

## 邮件与 Mailpit

`AccountNotificationService` 封装 Django email backend，提供 invitation/reset 两种纯文本邮件。开发 settings 使用 SMTP `mailpit:1025`；test 使用 locmem；production 不默认 Mailpit。Compose 增加 `axllent/mailpit:v1.30.7`，SMTP 仅容器网络，UI 映射 `127.0.0.1:8025:8025`，不创建 volume。

邮件可包含一次性代码和到期时间，但 API、日志、Admin 和审计不显示。验收邮箱只用 `.invalid`。

## 认证限流

使用 Django cache；开发/Compose 使用内置 RedisCache 与 `redis` 客户端，测试使用 LocMemCache。cache key 只包含用途和 HMAC 后的 normalized identifier/IP，不包含原始 username/email。

策略：login 每 IP 每分钟 10 次；password-reset request 每 identifier 每小时 5 次；invitation accept 每 IP 每小时 20 次；reset confirm 每 IP 每小时 20 次。reset request 超限仍返回通用 202且不发邮件；其余返回安全 429。无永久账号锁定。

## 审计

复用 AuditEvent，新增 action：invitation created/resent/revoked/accepted、password changed/reset completed、account activated/deactivated/role changed、session revoked、other/all sessions revoked。changes 白名单增加 username、email、target_role、role、session_id、client_platform、revoked_reason 和安全数量。不记录代码、digest、JTI、Token、密码或邮件正文。失败事务不产生成功审计。

## Flutter

继续使用单一 ApiClient/TokenStorage/AuthSessionStore/go_router/Riverpod。公开路由：`/forgot-password`、`/reset-password`、`/accept-invitation`；认证路由：`/settings/security`、`/settings/sessions`；system_admin 路由：`/admin/accounts`、`/admin/accounts/:id`、`/admin/invitations/new`。

新增 `features/account_security` 负责邀请接受、密码恢复/修改和会话；新增 `features/accounts` 负责 system_admin 管理。Repository 只复用 ApiClient；Widget 只调用 controller。登录字段改为 identifier，仍保留 single-flight refresh 和安全存储。所有密码表单防重复、失败保留输入并提供 PopScope；成功清理敏感 controller。

## CI

单一 `.github/workflows/ci.yml`，触发 main push、针对 main 的 PR 和 workflow_dispatch；`permissions: contents: read`，同分支 concurrency cancel-in-progress。

六个 job：backend-sqlite、backend-postgresql（PostgreSQL 17 + Redis 8）、flutter-quality、android-build（JDK 21）、windows-build、repository-safety。Python 3.12、Flutter 3.47.0。Actions 使用完整 SHA：checkout `11d5960a326750d5838078e36cf38b85af677262`、setup-python `a26af69be951a213d495a4c3e4e4022e16d87065`、setup-java `cf277c60eb25467037889841efdb72551f06f6c3`、flutter-action `1a449444c387b1966244ae4d4f8c696479add0b2`。

PR 默认只验证 Debug 产物存在并计算 SHA，不上传大产物。基础敏感扫描只是防误提交门禁，不宣称替代专业 secret scanner。

## 迁移兼容性

新增 accounts migration：User email 条件唯一约束、AccountInvitation、PasswordResetChallenge、AccountSession 及索引。迁移前必须再次检查大小写不敏感重复邮箱；冲突时 BLOCKED。旧 migration 不修改、不 squash/fake；现有 User/Employee/目录/审计和 Docker volume 保留。

部署后无 sid 旧 Token 全部失效；这是有意安全切换，文档和 UI要求重新登录。

## 安全限制

- 没有 MFA、Passkey、短信或外部身份源。
- 开发 Mailpit 不是生产邮件方案。
- 逐请求 Session DB 查询以正确性优先，后续再评估缓存。
- system_admin 自身与 superuser 的高风险管理仍留在 Django Admin。
- X-Request-ID 生产环境仍应由可信入口生成并校验。

## 后续阶段

第三阶段通过后只考虑审计导出/保留/归档、正式 applicationId/Windows publisher、生产邮件供应商、branch protection 和正式发布准备，不扩展薪资、考勤或复杂审批。
