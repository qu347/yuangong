# ADR-0004：HR 目录管理、RBAC、审计与 Token 吊销

- 状态：Accepted
- 日期：2026-08-17
- 适用阶段：第二期业务功能

## 背景

ADR-0003 已接受以下既有事实：系统采用 Django 模块化单体；`accounts.User` 是唯一用户模型；Flutter 只有一套 Riverpod/go_router/Dio/TokenStorage；目录 API 已实现 JWT 认证和只读员工/部门功能；Access Token 15 分钟、Refresh Token 7 天；角色使用 `employee`、`hr_admin`、`system_admin` 三个 Group。

第二阶段新增 HR 目录写操作、更细粒度 RBAC、操作审计、员工状态变更和 Refresh Token 服务端吊销。新决策不得被解释为 ADR-0003 已经具备的能力。

## 本阶段范围

- Department、Position、Employee 创建、编辑、显式状态 action，无物理删除 API。
- Django model permissions + Group 的目录写权限和审计读取权限。
- `sync_rbac` 幂等命令和 `seed_demo_data` 共享授权服务。
- append-only `AuditEvent`、只读审计 API 和 Admin 只读展示。
- SimpleJWT 官方 blacklist、Refresh rotation、logout、logout-all。
- 员工离职停用关联 User，并吊销该用户已登记的 Refresh Token。
- Flutter 能力驱动的管理入口、员工表单/状态 action、部门/岗位管理、审计列表和服务端退出。
- SQLite/PostgreSQL、OpenAPI、Docker、Windows、Android 真实验收。

## 非本阶段范围

不实现物理删除、薪资、考勤、审批、招聘、文件/头像、通知、多租户、外部 SSO/LDAP、动态字段级权限、复杂组织继承、账号邀请/密码重置或生产发布。

不新增工资、身份证、银行卡、住址、健康、私人邮箱/手机等高敏感字段。

## 权限模型

继续使用 Django 默认 model permissions，不建立第二套权限表。`sync_rbac` 只补充所需权限，不删除额外权限。

| 能力 | anonymous | employee | hr_admin | system_admin |
| --- | --- | --- | --- | --- |
| 登录/刷新/health/schema/docs | 允许 | 允许 | 允许 | 允许 |
| me 和目录读取 | 401 | 200 | 200 | 200 |
| Department add/change/action | 401 | 403 | 允许 | 允许 |
| Position add/change/action | 401 | 403 | 允许 | 允许 |
| Employee add/change/depart/reactivate | 401 | 403 | 允许 | 允许 |
| AuditEvent view | 401 | 403 | 允许 | 允许 |
| AuditEvent 写入/修改/删除 | 401 | 403 | 405 | 405 |
| 目录 DELETE | 401 | 403 | 405 | 405 |
| 用户/角色管理 | 401 | 403 | 不提供业务 API | 仅 Django Admin |

权限检查在对象查询前执行。写 API 使用显式 `DjangoModelPermissions` 风格 permission class：创建需要 `add_*`，PATCH 和状态 action 需要 `change_*`，审计读取需要 `audit.view_auditevent`。超级用户通过 Django 权限机制获得能力，但不能绕过业务完整性规则。

`/api/v1/me/` 增加稳定能力集合：

```text
can_manage_employees
can_manage_departments
can_manage_positions
can_view_audit
can_logout_all
```

Flutter 只用能力显示/保护路由；后端仍是权威边界。

## 目录写操作与无物理删除

沿用显式 URL 和 GenericAPIView，不把稳定只读 API 全量重构为 ViewSet。Serializer 负责输入校验，service 负责 `transaction.atomic()`、状态规则和审计，view 负责权限与 HTTP。

任何目录对象都不提供 DELETE。Admin 的 `has_delete_permission()` 返回 False。

### Department

- POST/PATCH 不允许直接写 `status`，状态只能通过 activate/deactivate。
- inactive Department 不能作为新父部门。
- deactivate 在存在 active 子部门、岗位或员工时返回 409 `resource_in_use`，只返回依赖数量。
- activate 幂等：已 active 返回成功且不重复审计。

### Position

- Department 必填且必须 active。
- 有任意 Employee 引用时不能移动 Department，返回 409。
- 有 active Employee 引用时不能 deactivate。
- activate/deactivate 幂等且不级联修改 Employee。

### Employee

- POST/PATCH 只允许目录字段，不允许普通 PATCH 修改 `employment_status` 或 `user`。
- Department 必须 active；Position 可空，存在时必须 active 且属于同一 Department。
- PATCH 可同时修改 Department 与 Position；只改 Department 而保留不匹配 Position 返回 400。
- Detail 返回 `updated_at`。PATCH 接受只写 `expected_updated_at`；不匹配时返回 409 `stale_object`，Flutter 重新加载并提示，不静默覆盖。

## 员工状态变更

### depart

选择幂等行为：active→departed 时执行变更；已 departed 再次调用返回 200、`changed=false`，不重复审计。

首次离职在同一事务中：

1. Employee 变为 departed。
2. 关联 User（如有）变为 inactive。
3. 当前用户所有已登记 Outstanding Refresh Token 加入 blacklist。
4. 记录 `depart`；账号从 active 变为 inactive 时另记录 `account_deactivate`。

### reactivate

选择幂等行为：departed→active；已 active 返回 `changed=false`。只恢复 Employee，不自动恢复 User。响应返回 `account_requires_activation`，账号恢复仅由 system_admin 在 Django Admin 处理。

## JWT blacklist 与 rotation

使用 SimpleJWT 官方 `rest_framework_simplejwt.token_blacklist`，不自行实现签名、解析或 Token 表。

- `ROTATE_REFRESH_TOKENS=True`
- `BLACKLIST_AFTER_ROTATION=True`
- refresh 前显式确认 token 对应 User 仍 active。
- rotation 返回新 Access + Refresh，旧 Refresh 自动 blacklist。

### logout

`POST /api/v1/auth/logout/` 需要 Access Token 和请求体 Refresh Token。验证签名、token_type 和所属 User。成功或同一用户已 blacklist 时幂等返回 204；无效 token 返回 400，其他用户 token 返回 403。只在首次 blacklist 时记录 `logout`，不记录 Token/JTI。

Flutter 无论服务端成功、Refresh 已失效或网络失败，都在尝试后清理本地 Token；UI 不展示原始响应。

### logout-all

`POST /api/v1/auth/logout-all/` 将当前用户所有未 blacklist 的 Outstanding Refresh Token 加黑，返回 `revoked_sessions`，重复调用返回 0；不影响其他用户。记录一次 `logout_all`，changes 只包含数量。

### Access Token 风险

普通 logout/logout-all 不使已签发 Access Token 立即失效，最长可能继续有效 15 分钟。Employee 离职会设置 User inactive；SimpleJWT 的实际 Access/Refresh 拒绝行为必须由真实测试确认。启用 blacklist 前签发、未登记的 Refresh Token 不能被历史迁移追溯，最长在原 7 天有效期内存在；本地演示账号在重新 seed/变更密码后重新获取 Token。

## 审计模型

在现有 `modules.audit` 空 app 中增加 `AuditEvent`：

```text
id UUID
actor User nullable SET_NULL
action enum
resource_type
resource_id stable text
resource_label safe text
changes JSON
source api/admin/system
request_id nullable
created_at
```

AuditEvent append-only：模型已存在记录不能 update/delete；Admin 禁止 add/change/delete；API 只提供 GET list/detail。

审计采用显式 recorder，不使用通用 post_save signal。service 在同一 `transaction.atomic()` 中完成业务保存与审计：任一失败均回滚。Admin 普通 create/update 通过 ModelAdmin hook 在 Admin 自身事务中记录，Employee status 在 Admin 中只读，不能绕过 action service。

`changes` 使用字段白名单，只记录真实变化。允许目录字段 ID/状态/工作目录字段；禁止 password、token、authorization、secret、数据库/Redis 凭据和完整 request body。Actor 删除后事件保留。

审计 API 默认 `-created_at`，page_size 20、最大 100，允许 actor/action/resource_type/resource_id/时间范围和受限 ordering；queryset `select_related("actor")`。

开发 `seed_demo_data` 是初始化例外：它调用 `sync_rbac`，但不为每个演示对象创建审计，避免重复初始化产生噪声；该例外只适用于显式 management command。

## 统一错误结构

继续沿用 `code/message/details/request_id`。稳定区分：

```text
400 validation_error
401 authentication_failed
403 permission_denied
404 not_found
405 method_not_allowed
409 resource_in_use
409 invalid_state_transition
409 uniqueness_conflict
409 stale_object
```

IntegrityError 映射为安全冲突，不返回 SQL、表名或约束名。无权限请求不因对象是否存在而改变 403。

## Flutter 管理能力

扩展现有 CurrentUser/AuthSessionStore/ApiClient/Repository，不创建第二套认证、网络、Token 或 Router。

- ApiClient 增加 PATCH、空 body action 和 204 方法。
- AuthRepository logout 先调用服务端，再在 finally 清理本地 Token；增加 logout-all。
- AuthSessionStore 缓存 capabilities，恢复/登录时来自 me，退出清空。
- 新路由：`/employees/new`、`/employees/:id/edit`、`/departments/manage`、`/positions/manage`、`/audit`。
- 未登录→login；无管理能力→employees；加载中不展示管理页面。

员工新增/编辑使用现有 Department/Employee Repository 扩展。表单只显示 active Department/Position，部门变化清除不兼容岗位；保存防重复、失败保留输入、成功刷新列表/详情。Employee 编辑发送 `expected_updated_at`。

depart/reactivate 使用确认对话框。reactivate 明确提示不会启用账号。

Department/Position 管理在 Windows 使用宽屏列表/编辑面板，在 Android 使用卡片/独立表单。Audit 页面只读并显示安全变更摘要。所有表单使用当前 Flutter 的 PopScope 保护未保存内容，保存中禁止离开。

## 迁移策略

1. 先验证 0ab87c7 无迁移差异，现有 PostgreSQL 只有 4/6/12 演示数据。
2. 安装 token_blacklist app 并应用其官方迁移。
3. `audit/0001_initial.py` 创建 AuditEvent。
4. organizations 迁移将 Position.department 从 nullable 改为必填；现有 6 个 Position 均有 Department，可兼容迁移。
5. 不修改既有迁移，不 fake/squash/flush/drop，不删除 volume。
6. SQLite 与 PostgreSQL 均从现有状态升级并验证演示数据计数不变。

## 测试策略

- 所有新行为先失败测试再最小实现。
- 后端对每个写端点覆盖 anonymous/employee/hr_admin/system_admin、业务冲突、事务回滚和审计。
- Token 测试覆盖 rotation/replay/logout/logout-all/inactive/跨用户隔离和日志脱敏。
- Audit 覆盖不可变、过滤分页、actor SET_NULL、敏感字段扫描和 Admin。
- Flutter 覆盖 capabilities、管理路由、表单四态、冲突、未保存保护、状态 action、审计和服务端退出。
- 完整套件在 SQLite/PostgreSQL、Windows/Android 和真实 Compose API 上运行。

## 已知限制

- applicationId/Windows 标识仍为开发占位符。
- Windows 本机仍可能需要进程级 `TrackFileAccess=false`。
- 中文路径 aapt/SDK XML 和既有 Pub Cache 元数据警告继续作为非阻塞项。
- 普通 logout 后 Access Token 最长有效 15 分钟。
- blacklist 启用前签发且未登记的 Refresh Token 无法追溯批量吊销。
- 没有复杂对象级/字段级 RBAC、审计导出/保留策略或账号恢复 Flutter 页面。
- 远程 `origin` 是上一轮用户授权上传产生的已知状态；第二阶段不 push。

## 后续阶段

第二阶段通过后只考虑正式身份标识、账号邀请/密码重置、更完整账号生命周期、审计导出/保留策略和基础 CI 协作；不直接进入薪资、考勤或复杂审批。

## 参考

- SimpleJWT 官方 blacklist app：<https://django-rest-framework-simplejwt.readthedocs.io/en/stable/blacklist_app.html>
- SimpleJWT rotation/blacklist settings：<https://django-rest-framework-simplejwt.readthedocs.io/en/latest/settings.html>
- Django 5.2 Group/model permissions：<https://docs.djangoproject.com/en/5.2/topics/auth/default/>
