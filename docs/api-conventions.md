# API 约定

## 基础规则

- API 前缀为 `/api/v1/`。
- JSON 字段使用 `snake_case`。
- 时间使用 ISO 8601；服务端存储和传输统一使用 UTC，客户端负责展示时区转换。
- 成功响应不返回调试信息、内部异常或堆栈。
- 健康检查不返回数据库主机、用户名或密码。

## 认证与目录端点

- `POST /api/v1/auth/login/` 与 `POST /api/v1/auth/refresh/` 公开。
- `GET /api/v1/me/`、部门、岗位和员工目录要求 Bearer JWT。
- `health`、OpenAPI schema 和 docs 保持公开；目录写 API本阶段不提供。

## 分页

员工列表使用 `page` 与 `page_size`，响应为 `count`、`next`、`previous`、`results`。默认页大小 20，最大 100，越界返回 400。

员工列表查询参数：

- `search`：姓名、工号、工作邮箱包含搜索。
- `department`：部门 UUID。
- `status`：`active` 或 `departed`。
- `ordering`：只允许 `employee_no`、`full_name`、`hire_date`、`created_at` 及倒序形式。

## 错误

稳定错误码使用英文大写下划线；用户可见消息使用简体中文。基础结构：

```json
{
  "code": "VALIDATION_ERROR",
  "message": "请求参数不正确",
  "details": {},
  "request_id": "optional-request-id"
}
```

请求 ID 未来从可信代理或后端中间件生成，使用响应头 `X-Request-ID` 并在错误响应中回显；当前不接受未校验客户端值作为审计标识。

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
