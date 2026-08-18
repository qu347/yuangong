# HR 目录管理、RBAC、审计与 Token 吊销实施计划

> 执行日期：2026-08-17
> 基线：`0ab87c7`
> 分支：`feature/hr-directory-management`

## 目标

在不扩展到薪资、考勤、审批、招聘或账号邀请的前提下，把现有只读员工目录升级为可审计、可授权、可吊销会话的 HR 管理功能，并由现有 Flutter Windows/Android 客户端提供能力驱动的管理界面。

## 架构边界

- 后端继续使用 Django 模块化单体、显式 URL、DRF GenericAPIView 和 SimpleJWT。
- Serializer 处理输入结构，service 在 `transaction.atomic()` 中处理业务规则和审计，view 只处理权限与 HTTP。
- RBAC 只使用 Django Group/model permissions；Flutter capabilities 只控制展示，不能替代后端授权。
- AuditEvent 是 append-only；目录对象不提供 DELETE；Employee 状态只能通过 depart/reactivate action 修改。
- Flutter 继续使用现有 Riverpod、go_router、Dio 和 TokenStorage，不创建第二套基础设施。
- 只支持 Android 和 Windows；不新增 iOS、Web、macOS、Linux。
- 第二阶段只做本地 4–6 个逻辑提交，不 push，不修改已知 `origin`。

## 技术栈

- Python 3.12、Django 5、Django REST Framework、SimpleJWT、drf-spectacular、pytest、PostgreSQL、Redis。
- Flutter 3.47+、Dart 3.10+、Riverpod 3、go_router 17、Dio 5。
- Docker Compose、PowerShell、Android ADB、Windows Flutter runner。

## 执行规则

每个行为先增加能失败的测试并确认失败原因，再做最小实现。每个任务结束运行对应聚焦测试；提交前运行该层完整测试。最终完整验收必须使用 SQLite、现有 Compose PostgreSQL/Redis、真实 HTTP、Windows 和 `employee_api36`，不得把未运行项写成通过。

## 任务 1：建立 RBAC 与 capabilities 合同

**文件**

- 新增：`backend/modules/accounts/rbac.py`
- 新增：`backend/modules/accounts/management/__init__.py`
- 新增：`backend/modules/accounts/management/commands/__init__.py`
- 新增：`backend/modules/accounts/management/commands/sync_rbac.py`
- 修改：`backend/modules/accounts/serializers.py`
- 修改：`backend/modules/employees/management/commands/seed_demo_data.py`
- 测试：`backend/tests/accounts/test_rbac.py`
- 测试：`backend/tests/accounts/test_me_api.py`

**测试先行**

1. 写测试证明 anonymous 为 401、employee 无写权限、hr_admin/system_admin 具有规定 add/change/view 权限。
2. 写 `sync_rbac` 重复执行测试，证明不重复 Group、不移除额外权限。
3. 写 `/api/v1/me/` capabilities 测试，证明五个稳定布尔字段来自后端权限。
4. 运行测试并确认因服务/命令/字段缺失而失败。

**实现**

1. 在 `rbac.py` 定义三个稳定角色、所需 ContentType/codename 映射和 `sync_rbac_permissions()`。
2. 命令只补充 Group 和权限，不清除部署方附加权限。
3. `seed_demo_data` 调用同一服务，不复制授权逻辑。
4. `CurrentUserSerializer` 输出 `capabilities`，超级用户沿用 Django 权限语义。

**验证**

```powershell
Set-Location backend
python -m pytest tests/accounts/test_rbac.py tests/accounts/test_me_api.py -q
python manage.py sync_rbac
python manage.py sync_rbac
```

## 任务 2：启用 Refresh rotation、blacklist 与服务端退出

**文件**

- 修改：`backend/config/settings/base.py`
- 新增：`backend/modules/accounts/tokens.py`
- 修改：`backend/modules/accounts/serializers.py`
- 修改：`backend/modules/accounts/views.py`
- 修改：`backend/modules/accounts/urls.py`
- 测试：`backend/tests/accounts/test_token_lifecycle.py`

**测试先行**

1. 覆盖 refresh rotation 返回新 Refresh、旧 Refresh replay 失败。
2. 覆盖 inactive User 的 Access/Refresh 实际行为。
3. 覆盖 logout 首次 204、同用户重复 204、无效 token 400、跨用户 token 403。
4. 覆盖 logout-all 只吊销当前用户 outstanding token、返回数量、重复返回 0。
5. 扫描日志与错误响应，断言不出现 Refresh、JTI、密码或 Authorization 值。

**实现**

1. 安装 `rest_framework_simplejwt.token_blacklist`，启用 rotation 和 `BLACKLIST_AFTER_ROTATION`。
2. 自定义 refresh serializer，在签发前拒绝 inactive User。
3. `tokens.py` 封装 token 所属用户验证、单 token 吊销和用户全部 outstanding token 吊销。
4. 添加 `POST /api/v1/auth/logout/` 与 `POST /api/v1/auth/logout-all/`；只返回安全错误。

**验证**

```powershell
Set-Location backend
python -m pytest tests/accounts/test_token_lifecycle.py -q
python manage.py makemigrations --check --dry-run
```

## 任务 3：实现 append-only AuditEvent 与只读 API

**文件**

- 新增：`backend/modules/audit/models.py`
- 新增：`backend/modules/audit/migrations/0001_initial.py`
- 新增：`backend/modules/audit/services.py`
- 新增：`backend/modules/audit/serializers.py`
- 新增：`backend/modules/audit/views.py`
- 新增：`backend/modules/audit/urls.py`
- 新增：`backend/modules/audit/admin.py`
- 修改：`backend/config/urls.py`
- 修改：`backend/modules/common/pagination.py`
- 测试：`backend/tests/audit/test_audit_model.py`
- 测试：`backend/tests/audit/test_audit_api.py`
- 测试：`backend/tests/audit/test_audit_admin.py`

**测试先行**

1. 覆盖 AuditEvent create、更新/删除拒绝、actor 删除后 SET_NULL。
2. 覆盖 employee 403、hr/system 200、POST/PATCH/DELETE 405。
3. 覆盖 actor/action/resource/time 过滤、默认排序、page_size 上限与查询数量。
4. 覆盖 Admin 无 add/change/delete，仅安全字段只读。
5. 覆盖 recorder changes 白名单，敏感键递归拒绝。

**实现**

1. 创建 UUID AuditEvent 和不可变 model guard。
2. recorder 只接受已定义 action/source、白名单字段和标量安全摘要。
3. API 使用 `select_related("actor")`、受限过滤/ordering 和 page_size 20/max 100。
4. Admin 只读展示，不允许任何写操作。

**验证**

```powershell
Set-Location backend
python -m pytest tests/audit -q
python manage.py makemigrations --check --dry-run
```

## 任务 4：统一安全错误和组织目录写服务

**文件**

- 修改：`backend/modules/common/exceptions.py`
- 新增：`backend/modules/common/permissions.py`
- 修改：`backend/modules/organizations/models.py`
- 新增：`backend/modules/organizations/migrations/0002_position_department_required.py`
- 修改：`backend/modules/organizations/serializers.py`
- 新增：`backend/modules/organizations/services.py`
- 修改：`backend/modules/organizations/views.py`
- 修改：`backend/modules/organizations/urls.py`
- 测试：`backend/tests/common/test_error_contract.py`
- 测试：`backend/tests/organizations/test_department_write_api.py`
- 测试：`backend/tests/organizations/test_position_write_api.py`

**测试先行**

1. 为 Department/Position 的 anonymous/employee/hr/system 四类权限写参数化测试。
2. 覆盖 create/PATCH、没有 DELETE、status 不能普通写、幂等 activate/deactivate。
3. 覆盖 inactive parent/department、active dependency、岗位移动和 unique 冲突。
4. 覆盖 service 保存或 audit 失败时整个事务回滚。
5. 覆盖 400/401/403/404/405/409 的稳定 `code/message/details/request_id`。

**实现**

1. 添加显式 model permission classes，权限在对象查询前判定。
2. Position.department 改为必填；serializer 做关系校验，service 做并发内重验和审计。
3. Department/Position list/detail 增加 POST/PATCH；action 使用显式 URL；不实现 destroy。
4. 把 IntegrityError 转换为不泄露 SQL/约束名的 `uniqueness_conflict`。

**验证**

```powershell
Set-Location backend
python -m pytest tests/common/test_error_contract.py tests/organizations -q
python manage.py makemigrations --check --dry-run
```

## 任务 5：实现 Employee 写入、并发检查和状态生命周期

**文件**

- 修改：`backend/modules/employees/serializers.py`
- 新增：`backend/modules/employees/services.py`
- 修改：`backend/modules/employees/views.py`
- 修改：`backend/modules/employees/urls.py`
- 修改：`backend/modules/employees/admin.py`
- 测试：`backend/tests/employees/test_employee_write_api.py`
- 测试：`backend/tests/employees/test_employee_status_api.py`
- 测试：`backend/tests/employees/test_employee_admin.py`

**测试先行**

1. 覆盖四类调用方对 create/PATCH/depart/reactivate 的矩阵和无 DELETE。
2. 覆盖部门/岗位 active 与同部门约束、不可写 status/user、唯一冲突。
3. 覆盖 `expected_updated_at` 成功和 stale_object 409。
4. 覆盖 depart 幂等、User inactive、该用户 outstanding token 全部吊销、其他用户不受影响、两个审计事件。
5. 覆盖 reactivate 幂等、User 不自动 active、`account_requires_activation`。
6. 注入审计失败，证明 Employee/User/token/audit 同事务回滚。

**实现**

1. Employee write serializer 只开放目录字段与只写 expected_updated_at。
2. service 使用 `select_for_update()` 重验状态/关系和乐观并发时间戳。
3. depart/reactivate action 不复用普通 PATCH；重复请求不产生重复审计。
4. Admin 将 status/user 设为受控只读，不提供删除。

**验证**

```powershell
Set-Location backend
python -m pytest tests/employees -q
```

## 任务 6：完成 Admin 审计、OpenAPI 与后端全套回归

**文件**

- 新增：`backend/modules/audit/admin_mixins.py`
- 修改：`backend/modules/organizations/admin.py`
- 修改：`backend/modules/employees/admin.py`
- 修改：`backend/modules/accounts/admin.py`
- 修改：`docs/api-conventions.md`
- 修改：`docs/security-baseline.md`
- 修改：`docs/development.md`
- 测试：`backend/tests/audit/test_admin_write_audit.py`
- 测试：`backend/tests/test_openapi_schema.py`

**测试先行与实现**

1. 先写 Admin create/update 审计测试，证明 changes 只含真实、安全变化，delete 禁止。
2. 写 OpenAPI 路由、method、response code 与 capabilities schema 测试。
3. 实现 Admin 审计 mixin，并让 Department/Position/Employee 普通 Admin 写入受保护。
4. 同步 API、安全、开发文档；明确 Access Token 15 分钟和历史 Refresh 风险。

**验证**

```powershell
Set-Location backend
python -m ruff format --check .
python -m ruff check .
python manage.py check
python manage.py makemigrations --check --dry-run
python -m pytest -q
```

## 任务 7：验证现有 PostgreSQL 升级和真实 HTTP 后端

**文件**

- 修改：`scripts/check.ps1`（仅在现有脚本未覆盖新增检查时）
- 新增或修改：`backend/tests/integration/test_directory_management_flow.py`
- 修改：`docs/environment-report.md`

**执行**

1. 只读记录升级前 migrations、Group/permissions、4/6/12 数据计数和状态分布。
2. 对现有 Compose PostgreSQL 应用官方 blacklist、audit 和 organizations 新迁移；不得 flush/drop/删 volume。
3. 运行 `sync_rbac`，验证重复执行结果一致。
4. 通过真实 HTTP 创建专用测试数据，覆盖登录、refresh rotation、RBAC、组织/员工 CRUD 子集、depart/reactivate、audit、logout-all。
5. 测试数据使用唯一前缀并通过业务 API 恢复到非活跃状态；不物理删除业务数据。
6. 验证 PostgreSQL/Redis health、容器状态、数据计数和敏感日志扫描。

**验证**

```powershell
docker compose -f deploy/docker-compose.yml config
docker compose -f deploy/docker-compose.yml ps
docker compose -f deploy/docker-compose.yml exec backend python manage.py showmigrations
docker compose -f deploy/docker-compose.yml exec backend python manage.py sync_rbac
docker compose -f deploy/docker-compose.yml exec backend python manage.py test
```

## 任务 8：扩展 Flutter capabilities、路由、网络与服务端退出

**文件**

- 修改：`apps/employee_app/lib/features/authentication/data/current_user.dart`
- 修改：`apps/employee_app/lib/features/authentication/data/auth_repository.dart`
- 修改：`apps/employee_app/lib/features/authentication/presentation/auth_session_store.dart`
- 修改：`apps/employee_app/lib/core/network/api_client.dart`
- 修改：`apps/employee_app/lib/core/network/api_endpoints.dart`
- 修改：`apps/employee_app/lib/app/router/app_router.dart`
- 修改：`apps/employee_app/lib/features/shell/presentation/adaptive_shell.dart`
- 测试：对应 `apps/employee_app/test/` 镜像路径测试

**测试先行**

1. 覆盖 CurrentUser capabilities 解析、缺失安全默认 false、退出清空。
2. 覆盖 ApiClient PATCH/action/204 和现有 single-flight refresh 不回退。
3. 覆盖 logout 服务端先尝试、所有结果 finally 清理本地；logout-all 返回数量。
4. 覆盖未登录、加载中、无能力和有能力的路由 guard。

**实现**

1. 扩展现有模型/仓储/store；不增加第二个 TokenStorage/Dio/Router。
2. 管理入口仅在 capability 为 true 时显示，深链仍由 guard 保护。

**验证**

```powershell
Set-Location apps/employee_app
flutter test test/core test/features/authentication test/app/router
```

## 任务 9：实现 Flutter 员工管理表单和状态 action

**文件**

- 修改：`apps/employee_app/lib/features/employees/data/employee.dart`
- 修改：`apps/employee_app/lib/features/employees/data/employee_repository.dart`
- 新增：`apps/employee_app/lib/features/employees/presentation/employee_form_controller.dart`
- 新增：`apps/employee_app/lib/features/employees/presentation/employee_form_page.dart`
- 修改：`apps/employee_app/lib/features/employees/presentation/employee_list_page.dart`
- 修改：`apps/employee_app/lib/features/employees/presentation/employee_detail_page.dart`
- 新增：`apps/employee_app/lib/core/widgets/unsaved_changes_guard.dart`
- 测试：对应员工 repository/controller/widget 测试

**测试先行与实现**

1. 覆盖新增/编辑 loading-empty-error-data 四态、校验、保存防重复、失败保留输入。
2. 覆盖 active 部门/岗位过滤、切换部门清除不兼容岗位。
3. 编辑发送 expected_updated_at；stale_object 提示重载而不覆盖。
4. 覆盖 depart/reactivate 确认、幂等响应、刷新列表/详情和账号不自动启用提示。
5. PopScope 在 dirty 时确认、保存中禁止离开；正常状态不误拦截。

## 任务 10：实现 Flutter 部门/岗位管理与审计页面

**文件**

- 扩展：`apps/employee_app/lib/features/departments/`
- 新增：`apps/employee_app/lib/features/positions/data/position.dart`
- 新增：`apps/employee_app/lib/features/positions/data/position_repository.dart`
- 新增：`apps/employee_app/lib/features/positions/presentation/position_management_page.dart`
- 新增：`apps/employee_app/lib/features/audit/data/audit_event.dart`
- 新增：`apps/employee_app/lib/features/audit/data/audit_repository.dart`
- 新增：`apps/employee_app/lib/features/audit/presentation/audit_page.dart`
- 测试：对应 repository/controller/widget 测试

**测试先行与实现**

1. 覆盖 Department/Position create/edit/action、409 依赖提示、表单防重复与刷新。
2. Windows 宽屏使用列表/编辑面板，Android 使用卡片/独立表单，断点固定 900。
3. Audit 只读列表覆盖 loading/empty/error/data、分页/筛选和安全 changes 摘要。
4. 无 capability 时入口隐藏且深链重定向。

**验证**

```powershell
Set-Location apps/employee_app
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

## 任务 11：双平台、自动化、文档和本地提交闭环

**文件**

- 修改：`README.md`
- 修改：`docs/development.md`
- 修改：`docs/environment-report.md`
- 修改：`docs/security-baseline.md`
- 修改：`docs/api-conventions.md`
- 修改：`scripts/check.ps1`（如任务 7 已修改则合并）

**Windows 验收**

1. 使用当前已验证的 Windows 工具链构建 Debug。
2. 实际启动 runner，验证进程、窗口存活、登录、管理入口和退出流程。
3. 只在已知工具链需要时使用进程级 `TrackFileAccess=false`，在报告中明确记录。

**Android 验收**

1. 使用默认 Gradle 用户目录构建 Debug APK，不用离线参数、临时代理或人工 Maven 缓存。
2. 在 `employee_api36` 安装并启动。
3. 用 ADB 验证进程、前台 Activity、真实 API 登录和至少一个只读/管理路由。

**最终命令**

```powershell
.\scripts\check.ps1
Set-Location apps/employee_app
flutter build windows --debug
flutter build apk --debug
Set-Location ../..
git diff --check
git status --short
```

**提交组织（总计 4–6 个，不 push）**

1. `docs: define HR directory management security design`
2. `feat(backend): add RBAC token revocation and audit`
3. `feat(backend): add audited directory management workflows`
4. `feat(flutter): add capability driven directory management`
5. `test(docs): validate phase two across real environments`

## 完成判定

- 本计划的权限矩阵、状态转换、审计、rotation/logout 和 Flutter 路由均有自动化测试证据。
- 旧测试与新增测试全部通过；SQLite/PostgreSQL 迁移无差异。
- 真实 Compose、PostgreSQL、Redis、Windows 和 Android 均有当轮运行证据。
- 4–6 个逻辑本地提交存在，工作树干净；`origin` 保留且第二阶段没有 push。
- 报告明确列出任何阻塞项、非阻塞警告和已知限制，不把 `NOT RUN` 写成通过。
