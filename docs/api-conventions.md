# API 约定

## 基础规则

- API 前缀为 `/api/v1/`。
- JSON 字段使用 `snake_case`。
- 时间使用 ISO 8601；服务端存储和传输统一使用 UTC，客户端负责展示时区转换。
- 成功响应不返回调试信息、内部异常或堆栈。
- 健康检查不返回数据库主机、用户名或密码。

## 认证与目录端点

- `POST /api/v1/auth/login/` 接受唯一的 `identifier`（用户名或账号邮箱）和密码；过渡期旧 `username` 可单独使用，两者不得并存。
- `POST /api/v1/auth/login/`、`POST /api/v1/auth/refresh/`、邀请接受和密码恢复公开。
- Refresh Token 成功刷新后 rotation，旧 Refresh Token 立即进入 blacklist。
- `POST /api/v1/auth/logout/` 需要 Access Token 和当前用户的 Refresh Token，成功返回 204。
- `POST /api/v1/auth/logout-all/` 吊销当前用户全部已登记 Refresh Token，返回 `revoked_sessions`。
- `GET /api/v1/me/`、部门、岗位和员工目录要求 Bearer JWT。
- `GET /api/v1/auth/sessions/` 只返回当前用户活跃会话和 `is_current`，不返回 Token/JTI；单会话、其他会话和管理员全部会话撤销使用显式 POST action。
- `GET/PATCH /api/v1/accounts/` 与邀请管理仅 system_admin 可用；业务角色调整只接受 `employee`/`hr_admin`。
- 邀请创建/重发响应只返回安全元数据。`POST /auth/invitations/accept/`、密码确认和密码修改成功返回 204，不自动登录。
- `POST /auth/password-reset/request/` 无论账号状态都返回相同 202 消息；不得从状态码、消息或 details 推断账号存在性。
- `/me/` 返回角色和稳定 capabilities；客户端只据此显示入口，后端权限仍是授权边界。
- Department、Position、Employee 支持 POST/PATCH 和显式状态 action，不提供 DELETE。
- AuditEvent 只支持 GET list/detail。
- `health`、OpenAPI schema 和 docs 保持公开。

目录写操作使用 Django model permissions：`employee` 只读；`hr_admin`、`system_admin` 可新增、修改和执行状态 action，并可读取审计。`sync_rbac` 幂等补齐权限，不移除额外授权。

## 分页

员工列表使用 `page` 与 `page_size`，响应为 `count`、`next`、`previous`、`results`。默认页大小 20，最大 100，越界返回 400。

员工列表查询参数：

- `search`：姓名、工号、工作邮箱包含搜索。
- `department`：部门 UUID。
- `status`：`active` 或 `departed`。
- `ordering`：只允许 `employee_no`、`full_name`、`hire_date`、`created_at` 及倒序形式。

## 错误

稳定错误码使用英文小写下划线；用户可见消息使用简体中文。基础结构：

```json
{
  "code": "validation_error",
  "message": "请求参数不正确。",
  "details": {},
  "request_id": "optional-request-id"
}
```

错误响应会回显 `X-Request-ID`，业务写服务把该值作为可选审计关联标识；调用方不得在其中放入 Token、账号或个人信息。生产部署应由可信入口生成并校验该值。

稳定 409 冲突码包括 `resource_in_use`、`invalid_state_transition`、`uniqueness_conflict` 与 `stale_object`。冲突详情只返回安全计数或可操作信息，不返回 SQL、表名和约束名。

## HTTP 状态码

- `200`：读取或更新成功。
- `201`：资源创建成功。
- `204`：成功且无响应体。
- `400`：参数或业务校验失败。
- `401`：未认证。
- `403`：已认证但无权限。
- `404`：资源不存在。
- `409`：状态冲突。
- `429`：请求过多。
- `500`：未知服务端错误。
- `503`：依赖服务暂时不可用，例如健康检查数据库失败。
