# ADR-0003：身份认证与员工目录最小纵向切片

- 状态：Accepted
- 日期：2026-08-17
- 适用阶段：第一期业务功能

## 背景

工程基线 `6102448` 已具备 Flutter Windows/Android 客户端、Django 模块化单体、PostgreSQL、Redis、Docker Compose、健康检查和 OpenAPI。本阶段需要在不扩展到完整 HR 系统的前提下，交付一条可测试、可运行、可演示的业务闭环：登录、当前用户、部门目录、员工查询与详情、退出登录。

只读审查确认：

1. Django 项目包为 `config`，settings 分为 `base`、`development`、`test`、`production`。
2. 已有 UUID 主键的自定义 `modules.accounts.User`，`AUTH_USER_MODEL="accounts.User"`，不得替换或重复创建。
3. `organizations` 与 `employees` 是空 app 壳，没有 Department、Position 或 Employee 模型。
4. DRF 尚未配置默认认证类和权限类；只有 health 显式公开。
5. OpenAPI 使用 drf-spectacular。
6. 数据库由 `POSTGRES_*` 驱动，测试默认 SQLite，可显式切换 PostgreSQL。
7. Redis 地址由 `REDIS_URL` 提供，本阶段认证和目录查询不强制依赖 Redis。
8. Flutter 已采用 feature-first 边界，且已有唯一的 `ApiClient`、go_router、Riverpod、`SecureStorageService` 与 `AppConfig`。
9. Flutter 未使用 Riverpod 代码生成或 build_runner，本阶段继续手写 Provider。
10. Windows 与 Android 均从 `API_BASE_URL` 读取 API 地址，分别使用现有 Dart define JSON。
11. `scripts/check.ps1` 会自动运行所有 Flutter 测试和 `backend/tests/test_*.py`。
12. 当前认证方式为空，DRF 采用框架默认 AllowAny；本阶段需要显式改为 JWT + IsAuthenticated，并逐个保留公开端点。
13. 当前 `ApiClient` 只提供 `getMap()`，以安全的 path/type 日志映射 Dio 错误；应扩展该类而不是创建第二套客户端。
14. 当前 go_router 初始路由是 `/dashboard`，没有重定向守卫；壳层使用 900 像素断点切换 NavigationRail/NavigationBar。
15. `SecureStorageService` 已封装 `flutter_secure_storage`，但没有 Token 专用键和生命周期抽象。
16. 后端测试集中在 `backend/tests` 并由 pytest-django 自动发现；Flutter 测试位于 `test`，另有不访问真实网络的 integration smoke test。
17. 仓库不存在与本阶段重复的认证 Repository、Token 模型、部门/岗位/员工模型或目录页面。

## 决策

### 范围

本阶段实现：

- JWT 登录、刷新和当前用户接口。
- Department、Position、Employee 三个目录领域模型和迁移。
- 部门列表/详情、岗位列表、员工列表/详情只读 API。
- 员工搜索、部门筛选、在职状态筛选、稳定排序和受限分页。
- Django Admin 目录数据管理。
- 幂等虚构演示数据命令。
- Flutter 登录、会话恢复、Token 安全存储、401 单航班刷新、路由守卫。
- Flutter 员工列表/详情、部门目录、加载/空/错误/重试、退出登录。
- Windows 与 Android 响应式布局和真实联调。

本阶段不实现员工/部门写 API、Flutter 管理表单、考勤、审批、薪资、招聘、上传、复杂审计、多租户、外部身份源或微服务。

### 领域模型

```text
accounts.User 0..1 ─── 0..1 employees.Employee
organizations.Department 1 ─── * organizations.Department (parent)
organizations.Department 1 ─── * organizations.Position
organizations.Department 1 ─── * employees.Employee
organizations.Position 0..1 ─── * employees.Employee
```

所有新模型使用 UUID 主键和 `created_at`/`updated_at`。Department 与 Position 使用 `active`/`inactive`；Employee 使用 `active`/`departed`。外键删除策略以 `PROTECT` 为主，岗位对员工使用 `SET_NULL`，本阶段不提供物理删除业务接口。

Department 在 `clean()` 中拒绝自身父级和祖先循环。Employee 在 `clean()` 中拒绝岗位所属部门与员工部门不一致。唯一约束覆盖部门编码、岗位编码和员工工号。

### 认证方案

采用 `djangorestframework-simplejwt` 5.5.1 和 DRF `JWTAuthentication`，不自行实现 JWT 签名、解析或密码校验。该版本明确支持 Django 5.2 与 Python 3.12。

- Access Token 有效期 15 分钟。
- Refresh Token 有效期 7 天。
- 本阶段不启用服务端黑名单；退出登录由客户端删除两种 Token。
- 登录标识暂用既有 `User.username`，仅作为可逆的开发期决定；正式工号/邮箱/企业身份源仍由 `OPEN_DECISIONS.md` 管理。
- 登录失败只返回“登录名或密码错误”一类通用消息。
- `/api/v1/me/` 对未关联 Employee 的 User 返回 `null` 目录字段，不产生 500。

Flutter 使用现有 `flutter_secure_storage`，在 `TokenStorage` 抽象中分别保存 Access/Refresh Token。测试注入内存实现，不访问系统凭据库。日志不记录请求头、密码、Token 或完整响应。

### 权限

使用 Django Groups：`system_admin`、`hr_admin`、`employee`。本阶段目录 API 为只读，三组已认证用户都可访问；匿名用户得到 401。写请求没有对应 API 方法并返回 405。

| 能力 | 未登录 | employee | hr_admin | system_admin |
| --- | --- | --- | --- | --- |
| health/schema/docs/login/refresh | 允许 | 允许 | 允许 | 允许 |
| me/部门/岗位/员工只读 API | 401 | 允许 | 允许 | 允许 |
| Django Admin | 不允许 | 不允许 | `is_staff` 时允许 | `is_staff`/超级用户时允许 |
| 目录写 API | 不提供 | 不提供 | 不提供 | 不提供 |

后端权限是权威边界，Flutter 路由守卫和界面显示不构成授权。

### API

```text
POST /api/v1/auth/login/
POST /api/v1/auth/refresh/
GET  /api/v1/me/
GET  /api/v1/departments/
GET  /api/v1/departments/{id}/
GET  /api/v1/positions/
GET  /api/v1/employees/
GET  /api/v1/employees/{id}/
```

目录字段使用 `snake_case`。员工列表响应沿用 DRF PageNumberPagination：`count`、`next`、`previous`、`results`。默认 `page_size=20`，允许客户端传 `page_size`，最大 100。

员工查询规则：

- `search`：对姓名、工号、工作邮箱执行不区分大小写的包含查询。
- `department`：接受 Department UUID。
- `status`：只接受 `active` 或 `departed`。
- `ordering`：只允许 `employee_no`、`full_name`、`hire_date`、`created_at` 及其倒序形式。
- 默认按 `employee_no` 稳定排序。
- 查询使用 `select_related("department", "position")`，避免明显 N+1。

Department 返回扁平、稳定排序的数据及 `parent` ID，Flutter 负责构建只读层级。Position 列表保持只读并按部门、名称排序。

### Flutter 组件与状态流

继续沿用现有层次，不创建第二套网络层：

```text
Widget
  → Riverpod Controller/Provider
    → AuthRepository / EmployeeRepository / DepartmentRepository
      → ApiClient
        → Dio + TokenStorage
```

`AuthSessionStore` 是轻量 `ChangeNotifier`，只维护 loading/authenticated/unauthenticated 路由状态。`AuthController` 负责初始化、登录、退出和当前用户；`ApiClient` 在请求前注入 Access Token，并通过单个共享 Refresh Future 合并并发 401。刷新请求使用独立 Dio，不再次进入认证拦截器；刷新失败时清空 Token、标记未登录并让 go_router 返回 `/login`。

路由为 `/login`、`/dashboard`、`/employees`、`/employees/:id`、`/departments`。未登录只能停留在 `/login`；已登录访问 `/login` 时重定向 `/employees`；直接打开详情路径时先经过相同守卫。保留现有 dashboard/health 能力，但登录成功默认进入员工目录。

员工列表 Controller 保存搜索、部门、状态和页码。搜索使用 350 毫秒防抖；筛选改变后回到第一页。Windows 宽屏使用表格式信息行和 NavigationRail，Android 使用卡片列表和 NavigationBar。两端共享 Repository、状态和路由。

### 错误处理

- API 客户端只记录请求路径与 Dio 错误类型，不记录 headers/body。
- 401 区分“可刷新”和“刷新失败”；403、校验、网络、协议错误映射为安全的中文 Failure。
- 登录页保留登录名，密码默认隐藏，提交期间禁用按钮。
- 列表和详情均提供加载、空、错误和重试状态，不显示堆栈或原始 Dio 内容。
- 现有统一异常响应结构继续保留，不建立第二套全局异常框架。

### 演示数据

`seed_demo_data` 使用 `update_or_create` 创建 4 个部门、6 个岗位、12 名虚构员工及三类 Group。演示登录用户密码只从 `EMPLOYEE_DEMO_PASSWORD` 进程环境变量读取；缺少时命令明确失败，不在源码、文档或输出中提供默认密码。重复执行对象数量不增长。

### 测试与迁移

每个行为先写失败测试，再最小实现。后端覆盖模型约束、JWT、权限、me、分页/搜索/筛选/详情、Admin、演示数据幂等、OpenAPI 与现有 health；同一套 pytest 在 SQLite 和 PostgreSQL 下运行。

Flutter 覆盖登录状态、Token 保存/清理、路由守卫、401 刷新合并和失败退出、列表四态、搜索/筛选、详情、部门目录、退出和响应式分支。Repository 与 TokenStorage 使用 Fake/Mock，不访问生产网络或系统凭据库。

迁移按 app 分开：`organizations/0001_initial.py` 创建 Department/Position，`employees/0001_initial.py` 创建 Employee 并依赖 accounts 与 organizations。禁止删除既有迁移、flush 数据库或删除 Docker volume。

## 备选方案

1. **Django Session + CSRF**：浏览器场景成熟，但原生 Windows/Android 的会话恢复、CSRF 和跨设备 Token 生命周期更复杂，不采用。
2. **自行实现 JWT**：依赖少，但加密、过期、错误处理和安全测试风险不可接受，不采用。
3. **引入 Riverpod 代码生成与新网络框架**：类型样板更少，但会增加 build_runner、生成文件和第二套抽象，偏离现有工程，不采用。

## 已知限制

- Android applicationId、namespace 和 Windows 发布标识仍为开发占位符。
- username 只是开发期登录标识，正式身份源未决定。
- JWT 退出登录不做服务端即时吊销；更严格的撤销策略留给后续安全阶段。
- 角色只覆盖本阶段目录读取和 Admin 入口，不是完整 RBAC。
- Redis 本阶段继续保留连接能力，但不用于 Token 或目录缓存。
- 不展示、不存储工资、身份证、银行卡、家庭住址等高敏感字段。

## 后续阶段

本切片通过后，下一阶段依次考虑 HR 管理员员工新增/编辑、部门与岗位维护、操作审计、员工状态变更和更细 RBAC；不直接跳到考勤、审批或薪资。
