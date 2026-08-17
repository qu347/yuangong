# 身份认证与员工目录 MVP 验收报告

验收日期：2026-08-17

工作区：`D:\员工管理`

## 1. 总体结论

```text
最终状态：PASSED WITH WARNINGS
功能分支：feature/employee-directory-mvp
工作区：主文档提交后已验证 clean；最终验收记录提交后再次复核
远程仓库：无
push：未执行
```

新增逻辑提交：

- `d505144 feat(backend): add authenticated employee directory API`
- `9019851 feat(app): add login and employee directory flow`
- `7528762 docs: document employee directory MVP`
- 验收记录与计划收尾：由本报告所在最终提交承载，哈希以最终 `git log` 和交付摘要为准

基础提交 `44adc69` 与 `6102448` 保持不变。未执行 reset、clean、restore、rebase、amend、push 或 Docker volume 删除。

## 2. 实际实现内容

### 后端

- 继续使用 UUID 自定义 `accounts.User`，没有建立第二套用户模型。
- 增加 SimpleJWT 5.5.1、JWTAuthentication 和默认 IsAuthenticated。
- Access Token 15 分钟，Refresh Token 7 天；登录失败使用通用错误，不输出账号存在性。
- 实现 me、部门、岗位和员工只读 API；health/schema/docs/login/refresh 保持公开。
- 员工列表支持姓名/工号/工作邮箱搜索、部门/状态筛选、受限排序和最大 100 的分页。
- 查询使用 `select_related("department", "position")`，测试固定为 2 条查询，避免明显 N+1。

### 数据库

- Department、Position、Employee 使用 UUID、时间戳和明确删除策略。
- Department 防止自身父级和祖先循环；Department/Position 编码及 employee_no 唯一。
- Employee 可选关联 User；岗位所属部门必须与员工部门一致。
- PostgreSQL 是真实运行数据库；SQLite 保持快速测试能力；Redis 本期不进入 Token 数据流。

### 认证与权限

- Django Groups：`employee`、`hr_admin`、`system_admin`。
- 三组已认证用户都可读取目录，匿名目录请求为 401；写方法不存在并返回 405。
- Django Admin 仍由 `is_staff`/超级用户控制，Flutter 不实现管理写页面。
- Flutter TokenStorage 分开保存 Access/Refresh；并发 401 只发起一次刷新，刷新失败清理 Token 并回 `/login`。

### Flutter

- 登录页：必填校验、密码隐藏、提交锁、用户安全错误、保留登录名。
- go_router：未登录/恢复中保护业务路径；已登录不能停留 `/login`；详情直达同样受保护。
- 员工列表：加载、成功、空、失败/重试、350ms 防抖、部门/状态筛选和分页。
- Windows 使用 DataTable/NavigationRail；Android 使用卡片/NavigationBar。
- 员工详情仅展示目录字段；部门页展示只读层级；退出登录是独立 shell 动作。

### 文档

- 更新 README、架构、开发、安全、API 约定和未决事项。
- 新增 ADR-0003、MVP 运行手册和详细实施计划。
- 文档不提供演示密码值，只说明安全的当前进程输入方式。

## 3. 模型和迁移

| 模型 | 关键字段/约束 | 迁移 |
| --- | --- | --- |
| Department | UUID、唯一 code、parent、active/inactive、sort_order、自引用/循环校验 | `organizations/0001_initial.py` |
| Position | UUID、唯一 code、可选 Department、active/inactive | `organizations/0001_initial.py` |
| Employee | UUID、唯一 employee_no、目录字段、Department PROTECT、Position SET_NULL、User 可选一对一、active/departed | `employees/0001_initial.py` |

验证结果：

- `migrate --noinput`：PASSED，PostgreSQL 无待应用迁移。
- `makemigrations --check --dry-run`：PASSED，No changes detected。
- 没有删除或修改既有 `accounts/0001_initial.py`。

## 4. API 验收

所有状态码来自真实 Compose API；Token 仅在进程内解析，未输出。

| 方法 | 路径 | 认证 | 实际状态码 | 结果 |
| --- | --- | --- | ---: | --- |
| GET | `/api/v1/health/` | 否 | 200 | PASSED |
| GET | `/api/schema/` | 否 | 200 | PASSED |
| GET | `/api/docs/` | 否 | 200 | PASSED |
| POST | `/api/v1/auth/login/` | 否 | 200 | PASSED |
| POST | `/api/v1/auth/refresh/` | 否 | 200 | PASSED |
| GET | `/api/v1/me/` | 是 | 200 | PASSED，Employee 已关联 |
| GET | `/api/v1/departments/` | 是 | 200 | PASSED，4 项 |
| GET | `/api/v1/positions/` | 是 | 200 | PASSED，6 项 |
| GET | `/api/v1/employees/` | 是 | 200 | PASSED，12 项 |
| GET | `/api/v1/employees/?search=EMP-0001` | 是 | 200 | PASSED，1 项 |
| GET | `/api/v1/employees/?status=departed` | 是 | 200 | PASSED，2 项 |
| GET | `/api/v1/employees/?department={uuid}` | 是 | 200 | PASSED，5 项 |
| GET | `/api/v1/employees/{id}/` | 是 | 200 | PASSED |
| GET | `/api/v1/employees/` | 否 | 401 | PASSED |

drf-spectacular 严格验证：PASSED，schema 10,702 字节，0 warning。

## 5. Flutter 验收

| 能力 | Windows | Android | 结果 |
| --- | --- | --- | --- |
| 登录 | 真实 API 通过 | 真实 API 通过 | PASSED |
| 路由守卫 | 自动化通过 | 自动化通过 | PASSED |
| 员工列表 | 加载 12 项 | 加载 12 项 | PASSED |
| 搜索 | `EMP-0001` | `EMP-0001` | PASSED |
| 筛选 | Controller/API 测试 | Controller/API 测试 | PASSED |
| 员工详情 | 工作邮箱/部门/岗位 | 工作邮箱/部门/岗位 | PASSED |
| 部门目录 | 4 个部门 | 4 个部门 | PASSED |
| 退出登录 | 回到 `/login` | 回到 `/login` | PASSED |
| 加载/空/错误/重试 | Widget 测试 | Widget 测试 | PASSED |
| 响应式分支 | DataTable/NavigationRail | Card/NavigationBar | PASSED |

真实集成测试均使用生产 EmployeeApp、Repository、Dio、路由和安全存储；密码只在运行进程的 Dart define 中短暂存在，未写入仓库或输出。

## 6. 自动化测试

| 检查 | 实际结果 |
| --- | --- |
| Flutter format | 59 个文件，0 变更 |
| Flutter analyze | No issues found |
| Flutter 单元/Widget | 55/55 PASSED |
| Windows 非网络 integration smoke | 1/1 PASSED |
| Windows 真实 API integration | 1/1 PASSED |
| Android 真实 API integration | 1/1 PASSED |
| Ruff format/check | 55 个文件，PASSED |
| Django check | 0 issues |
| SQLite pytest | 48/48 PASSED |
| PostgreSQL pytest | 48/48 PASSED |
| 迁移差异 | 0 |
| OpenAPI strict validate | PASSED |
| `scripts/check.ps1` | 提交前复验 34.3 秒，退出码 0 |
| PowerShell helper tests | 2/2 PASSED |

## 7. 实际运行证据

### Docker

- `api`：running。
- `db`：running / healthy。
- `redis`：running / healthy。
- health：HTTP 200。
- 当前 API 容器日志检查 33 行，错误模式 0。
- 未执行 `down -v`、reset、prune 或删除命名卷。

### Windows

- 正式构建：34.9 秒。
- EXE：`build/windows/x64/runner/Debug/employee_app.exe`。
- 大小：983,040 字节。
- SHA-256：`A67C6FD3ABDE0AAF9058F16998EB25B6A5FAF514617240DC3B433F763210A3A6`。
- 生产进程：PID 8516，窗口句柄 657810，Responding=true，正常退出码 0。
- 真实 UI 集成：登录→员工→搜索→详情→部门→退出，PASSED。

### Android

- AVD：`employee_api36` / `emulator-5554`，boot completed=1。
- 正式 APK 构建：47.5 秒。
- APK：`build/app/outputs/flutter-apk/app-debug.apk`。
- 大小：232,296,399 字节。
- SHA-256：`27B7EC93814630D2C5271B5E374CF2A5FC9BFD6FACC5AC5C4D13C06129A88C9C`。
- `adb install -r`：Success；`am start -W`：Status ok。
- 包：`com.yourcompany.employee_app`；PID 5049。
- `topResumedActivity`：`.MainActivity`；包进程 Fatal 模式计数 0。
- 真实 UI 集成：登录→员工→搜索→详情→部门→退出，PASSED。

## 8. 文件修改清单

| 路径/范围 | 修改原因 | 验证方式 |
| --- | --- | --- |
| `backend/config`、`requirements` | JWT、权限、Android emulator Host | check、pytest、真实 Android HTTP |
| `backend/modules/accounts` | login/refresh/me | JWT 测试、OpenAPI、真实 HTTP |
| `backend/modules/organizations` | Department/Position/Admin/API | 模型/API/Admin 测试、迁移 |
| `backend/modules/employees` | Employee/Admin/API/seed | 模型/API/幂等测试、真实 seed |
| `backend/tests` | 认证、权限、查询、Admin、seed、schema | SQLite/PostgreSQL 48/48 |
| `apps/employee_app/lib/core` | TokenStorage、Dio 刷新、错误映射 | 目标测试、analyze |
| `features/authentication` | 登录状态、页面、路由守卫 | 单元/Widget/真实集成 |
| `features/employees` | 列表、搜索/筛选、详情、响应式 | Repository/Controller/Widget/真实集成 |
| `features/departments` | 层级目录、错误重试 | Repository/Controller/Widget/真实集成 |
| `integration_test` | 非网络 smoke 与显式真实 API 流程 | Windows/Android 真实运行 |
| `README.md`、`docs` | 设计、API、安全、运行、限制 | diff check、安全审查 |

## 9. Git 结果

- 分支：`feature/employee-directory-mvp`。
- 基础：`6102448`，且 `44adc69` 保留。
- 功能提交：`d505144`、`9019851`。
- 主文档提交：`7528762`。
- 验收记录提交：本报告所在最终提交，哈希见最终交付摘要。
- 远程：0；push：否。
- 提交前高熵凭据模式：0；构建产物、缓存、`.dart_tool`、venv、Docker 数据均未暂存。

## 10. 遗留问题

### 阻塞

无。

### 高

无。

### 中

- SimpleJWT 本期未启用服务端黑名单，退出不能即时吊销已签发 Access Token；正式发布前需确定撤销策略。
- 正式企业登录标识和 AD/LDAP/SSO 尚未决定，本地 username 不能直接作为生产决策。

### 低

- 当前角色只覆盖目录读取和 Admin 入口，不是完整 RBAC。
- Redis 保持可用但本期未用于 Token 或目录缓存。

### 非阻塞警告

- Android applicationId/namespace 与 Windows 发布标识仍是开发占位符。
- Windows 构建仍需仅当前进程 `TrackFileAccess=false`。
- Flutter/aapt 对中文 APK 路径 manifest 检查会回退源 manifest；构建、安装和前台运行均已通过。
- SDK XML version 4 兼容提示仍存在，但 Gradle 构建成功。
- 既有 Pub Cache 元数据警告继续存在，本期未重复 `flutter pub get`。

## 11. 下一阶段建议

按顺序推进：

1. HR 管理员员工新增与编辑。
2. 部门和岗位维护。
3. 操作审计。
4. 员工状态变更。
5. 更细的 RBAC 与 Token 撤销策略。

不要直接跳到考勤、审批或薪资模块。

## 参考

- SimpleJWT 5.5.1 的包元数据声明支持 Django 5.2 与 Python 3.12：<https://pypi.org/project/djangorestframework-simplejwt/>
- DRF PageNumberPagination 响应和受限 OrderingFilter 约定：<https://www.django-rest-framework.org/api-guide/pagination/>、<https://www.django-rest-framework.org/api-guide/filtering/>
