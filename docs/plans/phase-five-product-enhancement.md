# 第五阶段产品能力完善实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在阶段四基线上交付 Dashboard、组织树、增强员工档案、全局搜索、HR 统计、轻量通知和可重复的性能验证。

**Architecture:** 保持 Django 模块化单体和 Flutter feature-first 分层。聚合/搜索放 common，组织树放 organizations，档案放 employees，通知放 accounts；客户端只复用 Riverpod、go_router 和 Dio。

**Tech Stack:** Django 5.2、DRF、PostgreSQL/SQLite、pytest、Flutter、Riverpod、go_router、Dio。

**Spec:** `docs/decisions/ADR-0008-product-enhancement.md`

## Global Constraints

- 仅支持 Windows 与 Android；不得创建 iOS、Web、macOS、Linux。
- 不引入微服务、消息队列、GraphQL、CQRS 或第二套权限/网络/状态/路由体系。
- 不实现考勤、审批、薪资、绩效、招聘、合同、培训、报销或资产。
- 不修改 `docs/environment-configuration.md`，不删除既有数据或测试。
- 所有行为变化先观察测试因缺少目标能力而失败，再写最小实现。

---

## 只读审查结论

### 当前能力

- `accounts.User` 是 UUID `AbstractUser`，稳定登录标识为 username/规范化 email；RBAC 为 employee、hr_admin、system_admin 三组 Django model permissions。
- `Employee` 当前包含工号、姓名、工作邮箱/电话、部门、岗位、状态、入职日期和可选 User 关联。
- `Department` 已有自关联 parent、自环/祖先循环校验；`Position` 必须属于一个部门。
- `AuditEvent` append-only，按资源与 action/time 建索引；HR/system 可读，只有 system 可导出。
- Flutter 登录后跳转 `/employees`，已有占位 Dashboard、900px 响应式 Shell、统一 loading/error 组件和 feature-first repository/controller/page。
- API 使用 `/api/v1/`、snake_case、稳定错误信封、默认 20/最大 100 的目录分页；SQLite/PostgreSQL 共用 pytest。

### 新增需求影响

- 数据库：Employee 六个可选档案字段和经理自关联；accounts.Notification；补充搜索/统计索引。
- API：Dashboard、HR statistics、部门树、全局搜索、通知列表/已读；员工 detail/write 扩展。
- Flutter：登录落点、Shell 搜索/通知入口、新 feature 数据链和档案详情/表单。
- 风险：经理/部门循环、统计越权、搜索结果泄露、聚合 N+1、10k 数据性能、窄屏溢出和历史数据兼容。

## Task 1：Dashboard 与 HR 聚合

**Files:** `backend/tests/test_product_enhancement_api.py`、`backend/modules/common/services.py`、`backend/modules/common/serializers.py`、`backend/modules/common/views.py`、`backend/modules/common/urls.py`

**Interfaces:** `dashboard_summary(user) -> dict`；`hr_statistics(user) -> dict`；GET `dashboard/summary/`、GET `statistics/hr/`。

- [ ] 写匿名、employee、hr_admin、空数据和聚合字面值断言的失败测试。
- [ ] 运行目标 pytest，确认路由 404/能力缺失导致失败。
- [ ] 用 `Count(filter=...)`、`TruncMonth` 和分组查询实现最小聚合服务/序列化/视图。
- [ ] 运行目标测试与 query-count 断言至通过。

## Task 2：组织架构树

**Files:** `backend/tests/test_product_enhancement_api.py`、`backend/modules/organizations/services.py`、`backend/modules/organizations/serializers.py`、`backend/modules/organizations/views.py`、`backend/modules/organizations/urls.py`

**Interfaces:** `build_department_tree(max_depth=12) -> list[dict]`；GET `departments/tree/`。

- [ ] 写 employee_count、稳定 children、空树、深度上限和常量查询数失败测试。
- [ ] 运行测试确认端点不存在。
- [ ] 一次 annotate 查询并内存组树；遇到孤儿、循环或深度超限返回 validation_error。
- [ ] 运行组织树与既有目录测试至通过。

## Task 3：增强员工档案

**Files:** `backend/modules/employees/models.py`、`backend/modules/employees/migrations/0002_employee_profile_fields.py`、`backend/modules/employees/serializers.py`、`backend/modules/employees/services.py`、`backend/tests/test_product_enhancement_models.py`、`backend/tests/test_product_enhancement_api.py`

**Interfaces:** Employee 可选 `avatar_url/gender/birthday/office_location/manager/description`；详情返回 manager summary。

- [ ] 写 migration 默认兼容、HTTPS avatar、本人/循环 manager、detail/write 的失败测试。
- [ ] 运行测试确认字段不存在。
- [ ] 添加可空字段、索引、模型校验、serializer 和 select_related(`manager`)。
- [ ] 运行模型/API/迁移漂移测试至通过。

## Task 4：全局搜索

**Files:** `backend/modules/common/search.py`、`backend/modules/common/serializers.py`、`backend/modules/common/views.py`、`backend/modules/common/urls.py`、`backend/tests/test_product_enhancement_api.py`

**Interfaces:** `search_directory(query, offset, limit) -> (count, results)`；GET `search/?q=&page=&page_size=`。

- [ ] 写姓名/工号/邮箱/部门/岗位、空查询、最大 50、匿名和分页失败测试。
- [ ] 运行目标测试确认 404。
- [ ] 使用 ORM `icontains` 参数绑定、三类固定投影和稳定分页实现。
- [ ] 运行搜索及既有目录搜索测试至通过。

## Task 5：轻量通知

**Files:** `backend/modules/accounts/models.py`、`backend/modules/accounts/migrations/0003_notification.py`、`backend/modules/accounts/notification_serializers.py`、`backend/modules/accounts/notification_views.py`、`backend/modules/accounts/urls.py`、`backend/tests/test_product_enhancement_api.py`

**Interfaces:** GET `notifications/` 返回 count/unread_count/results；PATCH `notifications/{id}/read/` 幂等返回 Notification。

- [ ] 写认证、用户隔离、分页、未读数和幂等已读失败测试。
- [ ] 运行目标测试确认模型/路由不存在。
- [ ] 添加模型迁移、当前用户 queryset 和 owner-only PATCH。
- [ ] 运行通知与账号安全回归测试至通过。

## Task 6：Flutter 业务能力

**Files:** `apps/employee_app/lib/features/{dashboard,search,notifications,departments}/**`、`apps/employee_app/lib/features/employees/**`、`apps/employee_app/lib/app/router/app_router.dart`、`apps/employee_app/lib/features/shell/presentation/adaptive_shell.dart`、对应 `test/features/**`

**Interfaces:** Repository 返回不可变模型；AsyncNotifier 暴露 retry/read；路由 `/dashboard`、`/search`、`/departments`、`/notifications`、`/employees/:id`。

- [ ] 分 feature 写 repository 解析和 widget loading/empty/error/retry/success 失败测试。
- [ ] 逐个运行测试，确认缺少模型/provider/入口而失败。
- [ ] 实现唯一 Dio repository、Riverpod controller 和响应式页面；员工详情增加组织/经理/位置/描述。
- [ ] 登录重定向改 `/dashboard`，Shell 增加搜索和通知入口，运行全部 Flutter 测试。

## Task 7：性能、文档与验收

**Files:** `backend/modules/employees/management/commands/seed_performance_data.py`、`backend/modules/employees/management/commands/benchmark_product_enhancement.py`、`backend/tests/test_product_enhancement_performance.py`、`docs/api-conventions.md`、`README.md`、`docs/product-enhancement-validation-report.md`

**Interfaces:** 幂等补齐 100/500/10000 虚构数据；基准命令输出 search/pagination/dashboard 毫秒值并在超标时非零退出。

- [ ] 写命令幂等、非删除和查询上限失败测试。
- [ ] 运行目标测试确认命令不存在。
- [ ] 批量创建固定前缀虚构数据并实现 `time.perf_counter` 热身/测量。
- [ ] 更新 OpenAPI/API 文档，运行 schema 严格验证。
- [ ] 运行 `scripts/check.ps1`、Windows/Android 构建和真实流程；报告每项 PASS/FAIL/NOT RUN 及证据。

## 自审

- ADR-0008 的 Dashboard、树、档案、搜索、统计、权限、敏感范围、性能和测试均映射到 Task 1-7。
- 文件、字段与路由命名在各任务间一致，没有未决占位内容。
- 不自动创建 commit；最终仅提供建议的 5-8 个提交切分和实际工作区状态。

## 增量补全任务（2026-08-20 已批准）

以下任务只补齐现有第五阶段实现的四个 UI/交互缺口，不替换既有 API、模型、路由基础设施或权限体系。

### Task 8：Flutter HR 统计图表页面

**Files:**

- Create: `apps/employee_app/lib/features/statistics/data/hr_statistics.dart`
- Create: `apps/employee_app/lib/features/statistics/data/hr_statistics_repository.dart`
- Create: `apps/employee_app/lib/features/statistics/presentation/hr_statistics_controller.dart`
- Create: `apps/employee_app/lib/features/statistics/presentation/hr_statistics_page.dart`
- Modify: `apps/employee_app/lib/app/router/app_router.dart`
- Modify: `apps/employee_app/lib/features/dashboard/presentation/dashboard_page.dart`
- Test: `apps/employee_app/test/features/product_enhancement_pages_test.dart`
- Test: `apps/employee_app/test/features/product_enhancement_repository_test.dart`

**Interfaces:**

- Consumes: `GET statistics/hr/` and existing `canViewAudit` capability as the HR/system UI-entry signal.
- Produces: `HrStatisticsRepository.fetchStatistics() -> Future<HrStatistics>` and route `/statistics`.

- [ ] **Step 1: Write failing repository and page tests**

```dart
expect(statistics.departmentHeadcount.single.count, 12);
expect(find.text('部门人数统计'), findsOneWidget);
expect(find.text('入职趋势'), findsOneWidget);
expect(find.text('基础人员分析'), findsOneWidget);
```

- [ ] **Step 2: Verify RED**

Run: `flutter test test/features/product_enhancement_repository_test.dart test/features/product_enhancement_pages_test.dart`

Expected: FAIL because the statistics model/repository/page and route do not exist.

- [ ] **Step 3: Implement minimal charts without dependencies**

Parse the existing response into immutable models. Render metric cards and proportional Material bars using `LayoutBuilder`, `FractionallySizedBox`, `LinearProgressIndicator`, and text labels; do not add a chart package.

- [ ] **Step 4: Verify GREEN**

Run: `flutter test test/features/product_enhancement_repository_test.dart test/features/product_enhancement_pages_test.dart test/app/router/app_router_test.dart`

Expected: PASS with employee users redirected away from `/statistics` and HR/system capability users allowed.

### Task 9：组织树部门成员查看

**Files:**

- Modify: `apps/employee_app/lib/features/departments/presentation/organization_tree_controller.dart`
- Modify: `apps/employee_app/lib/features/departments/presentation/organization_tree_page.dart`
- Test: `apps/employee_app/test/features/product_enhancement_pages_test.dart`

**Interfaces:**

- Consumes: `EmployeeRepository.fetchEmployees(departmentId: id, pageSize: 100)` and the existing authenticated employees API.
- Produces: `departmentMembersProvider(departmentId)` and a retryable department-member bottom sheet.

- [ ] **Step 1: Write failing interaction test**

```dart
await tester.tap(find.text('研发部'));
await tester.pumpAndSettle();
expect(find.text('林知远'), findsOneWidget);
expect(find.text('EMP-0001'), findsOneWidget);
```

- [ ] **Step 2: Verify RED**

Run: `flutter test test/features/product_enhancement_pages_test.dart --plain-name "organization tree loads department members"`

Expected: FAIL because department nodes do not handle taps.

- [ ] **Step 3: Implement provider-backed member loading**

Add a Riverpod family provider between Widget and EmployeeRepository. The sheet must expose loading, empty, error/retry, and success states and only show directory-safe employee information.

- [ ] **Step 4: Verify GREEN**

Run the same test and the existing department/employee page tests; expected PASS.

### Task 10：员工头像 URL 与失败降级

**Files:**

- Modify: `apps/employee_app/lib/features/employees/presentation/employee_detail_page.dart`
- Test: `apps/employee_app/test/features/employees/employee_detail_page_test.dart`

**Interfaces:**

- Consumes: existing `Employee.avatarUrl`.
- Produces: `EmployeeAvatar` that uses `Image.network` only for non-empty HTTPS URLs and shows the employee initial for empty/error cases.

- [ ] **Step 1: Write failing image and error-fallback widget tests**

```dart
expect(find.byType(Image), findsOneWidget);
expect(find.text('林'), findsNothing);
// After the image error completes:
expect(find.text('林'), findsOneWidget);
```

- [ ] **Step 2: Verify RED**

Run: `flutter test test/features/employees/employee_detail_page_test.dart`

Expected: FAIL because the detail avatar ignores `avatarUrl`.

- [ ] **Step 3: Implement minimal network image and fallback**

Use `ClipOval` + `Image.network(fit: BoxFit.cover, errorBuilder: ...)`; never log the URL or image response.

- [ ] **Step 4: Verify GREEN**

Run the same test; expected PASS for URL, empty URL, and failed image cases.

### Task 11：搜索结果分组与员工邮箱摘要

**Files:**

- Modify: `backend/modules/common/search.py`
- Modify: `backend/tests/test_product_enhancement_api.py`
- Modify: `apps/employee_app/lib/features/search/presentation/global_search_page.dart`
- Modify: `apps/employee_app/test/features/product_enhancement_pages_test.dart`
- Modify: `apps/employee_app/test/features/product_enhancement_repository_test.dart`

**Interfaces:**

- Consumes: unchanged `GET search/` route and `GlobalSearchResult.type`.
- Produces: employee subtitle containing employee number and work email when present; Flutter sections `员工`、`部门`、`岗位`.

- [ ] **Step 1: Write failing backend and Flutter grouping tests**

```python
assert employee_result["subtitle"] == "P5-SEARCH-001 · search.person@example.test · 智能平台 · 搜索工程师"
```

```dart
expect(find.text('员工'), findsOneWidget);
expect(find.text('部门'), findsOneWidget);
expect(find.text('岗位'), findsOneWidget);
expect(find.textContaining('lin.zhiyuan@example.test'), findsOneWidget);
```

- [ ] **Step 2: Verify RED**

Run backend search test and Flutter product-enhancement page test; expected FAIL because email/group headings are absent.

- [ ] **Step 3: Implement stable grouping**

Keep the endpoint and PostgreSQL ORM filters unchanged. Add `work_email` to the safe employee subtitle and render non-empty groups in fixed employee/department/position order.

- [ ] **Step 4: Verify GREEN**

Run targeted backend and Flutter tests; expected PASS without Elasticsearch or new dependencies.

### Task 12：增量文档与最终验收

**Files:**

- Modify: `docs/decisions/ADR-0008-product-enhancement.md`
- Modify: `docs/product-enhancement-validation-report.md`
- Modify: `README.md`

- [ ] Record the dependency-free chart choice, department-member provider flow, avatar fallback, and grouped-search contract.
- [ ] Run Flutter full tests, SQLite, PostgreSQL, strict OpenAPI, Windows build, Android build, and `scripts/check.ps1`.
- [ ] Report exact fresh counts and retain `PASSED WITH WARNINGS` when real-device/login click flows remain unavailable.

## 增量自审

- 四个批准缺口分别映射到 Task 8-11；Task 12 负责文档与验收。
- 不新增 dependency、数据库 migration、认证体系、后端权限模型或搜索基础设施。
- 数据接口只对搜索员工摘要做向后兼容扩展；HR 统计继续复用 `statistics/hr/`。

## 增量执行结果

- Task 8：完成。新增无第三方依赖的 HR 统计页面、repository/controller、Dashboard 入口和 employee/HR 路由权限测试。
- Task 9：完成。组织节点可按部门 UUID 加载最多 100 名目录成员，并提供加载、空、错误重试和成功状态。
- Task 10：完成。详情头像优先 HTTPS 网络图片，空 URL 与加载失败均降级首字头像。
- Task 11：完成。搜索 API 员工摘要增加工作邮箱，Flutter 按员工、部门、岗位分组。
- Task 12：完成。Flutter `106/106`、SQLite `194/194`、PostgreSQL `190 passed / 4 Windows-only skipped`、Strict OpenAPI、Windows Debug、Android Debug 与最终 `scripts/check.ps1`（Exit Code 0）均取得新鲜通过结果。
