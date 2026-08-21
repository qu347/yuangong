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
- AuditEvent 支持只读 list/detail；`GET /api/v1/audit-events/export.csv` 仅允许 system_admin，并复用 actor/action/resource/time/ordering 白名单筛选。
- `GET /api/v1/dashboard/summary/` 对所有已认证角色返回员工/部门/岗位聚合；最近操作只对具备审计读取权限的角色返回。
- `GET /api/v1/statistics/hr/` 只允许 HR/system 管理员，返回部门人数、岗位数、入职趋势和有数据时的性别/年龄分布。
- `GET /api/v1/departments/tree/` 一次查询返回最多 12 层的组织树、状态和员工人数。
- `GET /api/v1/search/` 使用 `q`、`page`、`page_size` 搜索员工、部门和岗位；默认 20，单页最大 50。
- `GET /api/v1/notifications/` 只返回当前用户通知和未读数；`PATCH /api/v1/notifications/{id}/read/` 幂等标记已读。
- `health`、OpenAPI schema 和 docs 保持公开。

目录写操作使用 Django model permissions：`employee` 只读；`hr_admin`、`system_admin` 可新增、修改和执行状态 action，并可读取审计。`sync_rbac` 幂等补齐权限，不移除额外授权。

审计导出默认最多 10000 行。超过上限返回 `400 / export_too_large`，details 只含 count/limit；成功响应为固定列 UTF-8 BOM CSV，公式危险前缀已中和。成功导出新增 `audit_exported`，只记录过滤摘要、格式与行数，不记录文件内容或完整查询字符串。

## 员工附件

- `GET /api/v1/employees/{employee_id}/attachments/`：返回 `count/next/previous/results` 分页；每项只含 `id`、`employee_id`、用户可见 `filename`、规范化 `file_type`、整数 `file_size`、上传者安全摘要和 `created_at`。客户端保留分页元数据并通过“加载更多”访问第 2 页及以后，跨页按 `-created_at, -id` 去重排序。
- `POST /api/v1/employees/{employee_id}/attachments/`：只接受 `multipart/form-data` 的 `file` 字段，成功返回 201。客户端不得提交内部文件名、存储路径、employee 或 uploaded_by。
- `GET /api/v1/attachments/{attachment_id}/download/`：返回授权后的流式二进制响应，设置安全 `Content-Disposition`、`Cache-Control: private, no-store` 和 `X-Content-Type-Options: nosniff`。
- `DELETE /api/v1/attachments/{attachment_id}/`：只执行软删除并返回 204，不删除磁盘文件。

允许 PDF、DOCX、XLSX、JPG/JPEG 和 PNG；JPEG 统一记录为 `jpg`。文件大小必须为 1 byte 至 10 MiB（含边界），扩展名和内容签名都由服务端验证。API 永不返回 `storage_path`、storage root 或绝对路径。

权限和对象范围如下：employee 只能列表/下载自身 Employee profile 的未删除附件，不能上传或删除；hr_admin 可管理未关联 system_admin/超级用户的员工附件；system_admin/超级用户可管理全部员工附件。除 system_admin/超级用户外，列表和下载必须先具有 `view_employeeattachment`，`add`/`change` 不替代 `view`。缺少读取、上传或软删除动作权限返回 403；已具备相应动作权限但目标超出对象可见范围、已软删除或不存在时返回安全 404，以隐藏对象存在性。后端权限是最终权威。

下载文件名策略只接受不含实际/解码后路径分隔符、控制/格式字符或响应头危险字符的 basename；basename 内部连续点不是路径穿越。响应文件名缺失或被拒绝时，客户端按响应元数据的规范 `file_type` 使用 `attachment.pdf/docx/xlsx/jpg/png`，保证 fallback 扩展名与 MIME 一致。

稳定附件错误码：

- `400 attachment_type_not_allowed`：扩展名不在白名单。
- `400 attachment_too_large`：超过 10 MiB。
- `400 attachment_invalid_content`：空文件、内容签名不匹配或非目标 OOXML ZIP。
- `400 attachment_file_missing`：上传请求缺少 `file`。
- `400 attachment_storage_conflict`：服务端生成路径在有限次数重试后仍冲突。
- `404 attachment_file_missing`：元数据存在但物理文件缺失；响应不得暴露内部路径。

Flutter 将 HTTP 400 的 `attachment_storage_conflict` 映射为“附件暂时无法保存，请重试。”，不把服务端存储条件误报为普通输入校验。

附件列表使用 `select_related` 读取 employee/uploaded_by。合同测试证明 1 条和 20 条结果均为 3 次查询，不随附件数增长；附件区域独立加载，不向 10,000 员工目录查询附加附件预取。

## 分页

员工列表使用 `page` 与 `page_size`，响应为 `count`、`next`、`previous`、`results`。默认页大小 20，最大 100，越界返回 400。

员工列表查询参数：

- `search`：姓名、工号、工作邮箱包含搜索。
- `department`：部门 UUID。
- `status`：`active` 或 `departed`。
- `ordering`：只允许 `employee_no`、`full_name`、`hire_date`、`created_at` 及倒序形式。

员工详情在原目录字段基础上增加可选 `avatar_url`、`gender`、`birthday`、`office_location`、直属负责人摘要 `manager` 和 `description`。头像仅接受 HTTPS URL；不提供上传。禁止身份证、银行卡、工资、家庭住址和健康信息。

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
