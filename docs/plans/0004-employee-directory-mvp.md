# Employee Directory MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付登录、当前用户、部门目录、员工搜索/筛选/详情和退出登录组成的 Windows/Android 最小业务纵向闭环。

**Architecture:** 后端沿用 Django 模块化单体，以 SimpleJWT 保护 DRF 只读目录 API；Flutter 沿用现有 feature-first、Riverpod、go_router、Dio 和 Secure Storage，通过 Repository 与单航班刷新拦截器连接 API。PostgreSQL 是真实权威数据库，SQLite 保持快速测试能力，Redis 本阶段不进入认证数据流。

**Tech Stack:** Flutter 3.47、Dart 3.13、Riverpod 3.4、go_router 17.5、Dio 5.11、flutter_secure_storage 11、Django 5.2.17、DRF、SimpleJWT 5.5.1、drf-spectacular、PostgreSQL 17、Redis 8、Docker Compose、pytest、Ruff。

## Global Constraints

- 只支持 Windows 与 Android，不创建 iOS、Web、macOS 或 Linux 文件。
- 保留 `accounts.User` 与 `AUTH_USER_MODEL="accounts.User"`，不得建立第二套用户模型。
- 登录标识仅在本 MVP 中使用现有 username；正式身份源继续保持未决。
- API 只实现读取，不提供员工、部门或岗位写接口。
- Flutter Widget 不直接调用 Dio 或 Secure Storage；不引入 Riverpod 代码生成。
- 不打印或提交密码、JWT、Refresh Token、Authorization、数据库凭据或真实员工数据。
- 不执行 reset、clean、rebase、amend、push、flush、删除迁移或删除 Docker volume。
- C 盘 Pub Cache 警告不属于本阶段阻塞项；Flutter 依赖不变，不运行 `flutter pub get`。
- 用户要求全部自动化和真实验收通过后再创建 2 至 4 个逻辑本地提交。

---

### Task 1: JWT 认证与当前用户契约

**Files:**
- Modify: `backend/requirements/base.txt`
- Modify: `backend/config/settings/base.py`
- Modify: `backend/config/urls.py`
- Create: `backend/modules/accounts/serializers.py`
- Create: `backend/modules/accounts/views.py`
- Create: `backend/modules/accounts/urls.py`
- Test: `backend/tests/test_auth_api.py`
- Modify: `backend/tests/test_schema.py`

**Interfaces:**
- Consumes: existing `accounts.User`, global exception handler, drf-spectacular.
- Produces: `POST auth/login/`, `POST auth/refresh/`, `GET me/`, global `JWTAuthentication` and `IsAuthenticated`.

- [x] **Step 1: Write failing authentication tests**

Add tests that create a UUID User and assert:

```python
login = client.post("/api/v1/auth/login/", {"username": "demo", "password": password})
assert login.status_code == 200
assert set(login.json()) == {"access", "refresh"}
assert client.post("/api/v1/auth/login/", {"username": "demo", "password": "wrong"}).status_code == 401
assert client.get("/api/v1/me/").status_code == 401
```

Use the returned Access Token only inside the test request header and never print it. Test refresh returns a new valid Access Token. Test `me` without Employee returns user fields plus `employee_id`, `employee_no`, `department` as null and an empty roles list.

- [x] **Step 2: Verify RED**

Run:

```powershell
backend\.venv\Scripts\python.exe -m pytest backend\tests\test_auth_api.py backend\tests\test_schema.py -q
```

Expected: FAIL because auth routes, SimpleJWT dependency, and JWT security schema do not exist.

- [x] **Step 3: Add SimpleJWT and settings**

Add `djangorestframework-simplejwt==5.5.1`. Configure:

```python
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": ("rest_framework.permissions.IsAuthenticated",),
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "EXCEPTION_HANDLER": "modules.common.exceptions.api_exception_handler",
}
SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=15),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=7),
    "ROTATE_REFRESH_TOKENS": False,
}
```

Create `LoginSerializer(TokenObtainPairSerializer)` with the generic Chinese failure message, `LoginView`, `TokenRefreshView`, and authenticated `MeView`. Register routes under `/api/v1/`.

- [x] **Step 4: Verify GREEN and regressions**

Run the targeted tests, then all backend tests. Expected: authentication tests pass; existing health/schema tests remain green and health stays public.

### Task 2: Department, Position, and Employee models

**Files:**
- Create: `backend/modules/organizations/models.py`
- Create: `backend/modules/organizations/migrations/0001_initial.py`
- Create: `backend/modules/employees/models.py`
- Create: `backend/modules/employees/migrations/0001_initial.py`
- Test: `backend/tests/test_directory_models.py`

**Interfaces:**
- Produces: `Department`, `Position`, `Employee`, status choices, `Employee.user` reverse name `employee_profile`.

- [x] **Step 1: Write failing model tests**

Cover unique Department code, unique Position code, unique employee number, UUID IDs, timestamps, self-parent rejection, ancestor-cycle rejection, protected referenced departments, and position/employee department consistency:

```python
department.parent = department
with pytest.raises(ValidationError):
    department.full_clean()
```

- [x] **Step 2: Verify RED**

Run `pytest backend/tests/test_directory_models.py -q`. Expected: import failures for missing models.

- [x] **Step 3: Implement minimal models**

Use UUID keys, TextChoices, `PROTECT`, `SET_NULL`, uniqueness, stable Meta ordering, and `clean()` validation exactly as ADR-0003 defines. Do not add high-sensitivity fields or delete APIs.

- [x] **Step 4: Generate and inspect migrations**

Run from `backend`:

```powershell
.\.venv\Scripts\python.exe manage.py makemigrations organizations employees
.\.venv\Scripts\python.exe manage.py migrate --noinput --settings=config.settings.test
.\.venv\Scripts\python.exe manage.py makemigrations --check --dry-run
```

Inspect dependencies: employees migration must depend on accounts and organizations; no existing migration may be modified.

- [x] **Step 5: Verify GREEN**

Run model tests and full backend pytest. Expected: all model constraints pass in SQLite.

### Task 3: Authenticated directory APIs

**Files:**
- Create: `backend/modules/common/pagination.py`
- Create: `backend/modules/organizations/serializers.py`
- Create: `backend/modules/organizations/views.py`
- Create: `backend/modules/organizations/urls.py`
- Create: `backend/modules/employees/serializers.py`
- Create: `backend/modules/employees/views.py`
- Create: `backend/modules/employees/urls.py`
- Modify: `backend/config/urls.py`
- Test: `backend/tests/test_directory_api.py`
- Modify: `backend/tests/test_schema.py`

**Interfaces:**
- Produces: `DirectoryPagination(page_size=20,max_page_size=100)`, read-only department/position/employee endpoints and nested summary JSON.

- [x] **Step 1: Write failing API tests**

Create fictional fixtures and assert anonymous list/detail returns 401; authenticated GET returns 200; POST returns 405. Cover:

```python
client.get("/api/v1/employees/?search=EMP-001")
client.get(f"/api/v1/employees/?department={department.id}")
client.get("/api/v1/employees/?status=active&page=1&page_size=2")
client.get("/api/v1/employees/?ordering=-full_name")
```

Assert `count/next/previous/results`, exact directory-safe fields, 400 for invalid department/status/page_size, and 404 for missing employee. Use query capture or `django_assert_num_queries` to guard against N+1.

- [x] **Step 2: Verify RED**

Run `pytest backend/tests/test_directory_api.py backend/tests/test_schema.py -q`. Expected: 404 routes.

- [x] **Step 3: Implement serializers, pagination, and generic views**

Use `ListAPIView`/`RetrieveAPIView`, DRF `SearchFilter` and `OrderingFilter`, explicit `search_fields` and `ordering_fields`, plus validated department/status query handling. Employee querysets must use `select_related("department", "position")`.

- [x] **Step 4: Document OpenAPI parameters**

Use `extend_schema`/`OpenApiParameter` so schema shows `search`, `department`, `status`, `page`, `page_size`, and `ordering`, and JWT Bearer security appears on protected operations.

- [x] **Step 5: Verify GREEN**

Run targeted API/schema tests and full backend pytest. Expected: all new endpoints and existing health/schema pass.

### Task 4: Admin and idempotent fictional seed data

**Files:**
- Create: `backend/modules/organizations/admin.py`
- Create: `backend/modules/employees/admin.py`
- Create: `backend/modules/employees/management/__init__.py`
- Create: `backend/modules/employees/management/commands/__init__.py`
- Create: `backend/modules/employees/management/commands/seed_demo_data.py`
- Test: `backend/tests/test_admin.py`
- Test: `backend/tests/test_seed_demo_data.py`

**Interfaces:**
- Produces: registered Admin models and `python manage.py seed_demo_data` using `EMPLOYEE_DEMO_PASSWORD`.

- [x] **Step 1: Write failing Admin and seed tests**

Assert Department/Position/Employee are registered. Set a process-only fictional password in the test, run the command twice, and assert exact stable counts: 3 groups, 4 departments, 6 positions, 12 employees, 1 demo login user. Assert missing password environment raises `CommandError` and output never contains the password.

- [x] **Step 2: Verify RED**

Run both test files. Expected: models are unregistered and command is unknown.

- [x] **Step 3: Implement Admin and command**

Admin uses list display, search fields, list filters, and raw/autocomplete user relation as appropriate. Seed command uses `update_or_create`, `example.test` email addresses, fictional names and non-private work phone placeholders. It reads the password only through `os.environ["EMPLOYEE_DEMO_PASSWORD"]` and never echoes it.

- [x] **Step 4: Verify GREEN and idempotency**

Run targeted tests, then invoke the command twice against the development database with a generated process-only password and compare object counts without printing the value.

### Task 5: Backend PostgreSQL and HTTP integration gate

**Files:**
- Modify only on reproduced failures: backend implementation/tests from Tasks 1-4.

**Interfaces:**
- Validates: migrations and pytest against the real Compose PostgreSQL service; real JWT/API HTTP flow.

- [x] **Step 1: Run static and migration checks**

Run Ruff format/check, Django check, `makemigrations --check --dry-run`, and migrate using the project venv.

- [x] **Step 2: Run SQLite and PostgreSQL pytest**

Use the in-memory Compose config to populate process variables without printing credentials. Run the full suite once with default SQLite and once with `TEST_DATABASE_ENGINE=postgresql`, `EXPECTED_DATABASE_VENDOR=postgresql`.

- [x] **Step 3: Rebuild Compose and seed**

Run `docker compose ... up -d --build`, wait for db/redis healthy and api running, then seed twice with a generated process-only password. Do not delete volumes.

- [x] **Step 4: Verify real HTTP flow**

Issue real requests for health/schema/docs, login, refresh, me, departments, positions, employee search/filter/detail, and anonymous 401. Parse tokens only in memory and output status/field counts, never token strings.

### Task 6: Flutter TokenStorage, authentication, and refresh-safe ApiClient

**Files:**
- Create: `apps/employee_app/lib/core/storage/token_storage.dart`
- Modify: `apps/employee_app/lib/core/network/api_client.dart`
- Modify: `apps/employee_app/lib/core/network/api_endpoints.dart`
- Extend: `apps/employee_app/lib/core/errors/app_exception.dart`
- Extend: `apps/employee_app/lib/core/errors/failure.dart`
- Create: `apps/employee_app/lib/features/authentication/data/auth_tokens.dart`
- Create: `apps/employee_app/lib/features/authentication/data/current_user.dart`
- Create: `apps/employee_app/lib/features/authentication/data/auth_repository.dart`
- Create: `apps/employee_app/lib/features/authentication/presentation/auth_session_store.dart`
- Create: `apps/employee_app/lib/features/authentication/presentation/auth_controller.dart`
- Test: `apps/employee_app/test/core/storage/token_storage_test.dart`
- Test: `apps/employee_app/test/core/network/api_client_auth_test.dart`
- Test: `apps/employee_app/test/features/authentication/auth_controller_test.dart`

**Interfaces:**
- Produces: `TokenStorage`, `AuthTokens`, `CurrentUser`, `AuthRepository`, `AuthSessionStore`, `AuthController`, authenticated `ApiClient` methods.

- [x] **Step 1: Write failing Token and auth state tests**

Use memory/fake storage. Assert login stores access/refresh separately, restore calls me, logout deletes both, invalid credentials produce safe Chinese failure, and no test accesses real secure storage.

- [x] **Step 2: Write failing Dio refresh tests**

Use a fake `HttpClientAdapter` and injected main/refresh Dio clients. Assert Authorization injection, one refresh for two concurrent 401 responses, successful original-request retry, refresh request does not recurse, and refresh failure clears tokens and marks unauthenticated. Do not assert/log raw token text outside in-memory fixtures.

- [x] **Step 3: Verify RED**

Run the three new test files. Expected: missing classes/providers.

- [x] **Step 4: Implement minimal storage and network flow**

Wrap existing `SecureStorageService`; extend the single existing `ApiClient` with `getMap`, `postMap`, auth-skip metadata, interceptor injection, a shared `_refreshFuture`, separate refresh Dio, retry guard, safe status mapping, and auth-loss callback.

- [x] **Step 5: Implement Auth Repository/Controller**

`AuthController` is a hand-written `AsyncNotifier<CurrentUser?>`; it initializes from stored tokens, calls me, transitions `AuthSessionStore`, handles login/logout, and never owns URL strings.

- [x] **Step 6: Verify GREEN**

Run targeted Flutter tests, `dart format`, and `flutter analyze` through the existing helper.

### Task 7: Login page and go_router authentication guard

**Files:**
- Modify: `apps/employee_app/lib/app/app.dart`
- Modify: `apps/employee_app/lib/app/router/app_router.dart`
- Create: `apps/employee_app/lib/features/authentication/presentation/login_page.dart`
- Test: `apps/employee_app/test/app/router/app_router_test.dart`
- Test: `apps/employee_app/test/features/authentication/login_page_test.dart`

**Interfaces:**
- Produces: `/login` and guard for `/dashboard`, `/employees`, `/employees/:id`, `/departments`.

- [x] **Step 1: Write failing router tests**

Assert unauthenticated business routes redirect to `/login`, authenticated `/login` redirects to `/employees`, loading state does not loop, direct employee detail is guarded, and auth loss redirects once.

- [x] **Step 2: Write failing login Widget tests**

Assert username/password validation, obscured password, loading button lock, failed login keeps username and shows safe error, successful login changes auth state.

- [x] **Step 3: Verify RED**

Run router/login test files. Expected: missing route/store/page behaviors.

- [x] **Step 4: Implement router and LoginPage**

Expose a testable `createAppRouter(AuthSessionStore)` and provider-owned disposal. Watch `authControllerProvider` in `EmployeeApp` to start restoration. Login Widget only calls the controller.

- [x] **Step 5: Verify GREEN**

Run targeted tests and existing app smoke tests, updating smoke setup with fake authenticated state rather than bypassing the guard.

### Task 8: Employee and department Flutter directory

**Files:**
- Create: `apps/employee_app/lib/features/employees/data/employee.dart`
- Create: `apps/employee_app/lib/features/employees/data/employee_page.dart`
- Create: `apps/employee_app/lib/features/employees/data/employee_repository.dart`
- Create: `apps/employee_app/lib/features/employees/presentation/employee_directory_controller.dart`
- Create: `apps/employee_app/lib/features/employees/presentation/employee_list_page.dart`
- Create: `apps/employee_app/lib/features/employees/presentation/employee_detail_page.dart`
- Create: `apps/employee_app/lib/features/departments/data/department.dart`
- Create: `apps/employee_app/lib/features/departments/data/department_repository.dart`
- Create: `apps/employee_app/lib/features/departments/presentation/department_controller.dart`
- Create: `apps/employee_app/lib/features/departments/presentation/department_page.dart`
- Modify: `apps/employee_app/lib/app/router/app_router.dart`
- Modify: `apps/employee_app/lib/features/shell/presentation/adaptive_shell.dart`
- Modify: `apps/employee_app/lib/features/dashboard/presentation/dashboard_page.dart`
- Test: matching repository/controller/page tests under `apps/employee_app/test/features/`

**Interfaces:**
- Produces: paginated employee directory, detail, department hierarchy, responsive shell logout action.

- [x] **Step 1: Write failing model/repository tests**

Assert complete JSON parsing, paginated query construction, URL encoding, safe malformed-data failure, employee detail lookup, and department list parsing.

- [x] **Step 2: Write failing controller tests**

Assert initial loading/success, empty results, failure and retry, 350 ms search debounce, department/status filters resetting page, and next/previous paging boundaries.

- [x] **Step 3: Write failing Widget tests**

Cover employee list loading/success/empty/error/retry, desktop table-like branch, compact card branch, search/filter controls, detail fields, department hierarchy, and logout button. Existing 900 px shell breakpoint tests remain.

- [x] **Step 4: Verify RED**

Run only new feature tests. Expected: missing files/providers/widgets.

- [x] **Step 5: Implement data and controller layers**

Repositories call only `ApiClient`; controllers own UI query state and debounce timer; JSON models expose only directory fields.

- [x] **Step 6: Implement responsive pages and shell**

Keep dashboard/health. Navigation destinations become dashboard, employees, departments; logout is a separate action. Employee detail displays only directory-safe fields.

- [x] **Step 7: Verify GREEN and full Flutter suite**

Run format, analyze, all unit/widget tests, and the non-network integration smoke test. Record the new actual count.

### Task 9: Full-stack real clients, documentation, and final commits

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/development.md`
- Modify: `docs/security-baseline.md`
- Modify: `docs/api-conventions.md`
- Modify: `docs/OPEN_DECISIONS.md`
- Create: `docs/employee-directory-mvp.md`
- Create: `docs/employee-directory-mvp-validation-report.md`
- Modify: `docs/plans/0004-employee-directory-mvp.md`

**Interfaces:**
- Produces: reproducible runbook, final evidence report, Windows/Android artifacts, 2-4 logical commits.

- [x] **Step 1: Update documentation**

Document Docker startup, process-only demo password variable, idempotent seed, roles, endpoints, tests, Windows/Android commands, configuration files, security boundaries, known placeholders, and excluded modules. Never include an example password value.

- [x] **Step 2: Run unified automation**

Run `scripts/check.ps1`, SQLite pytest, PostgreSQL pytest, migrations check, API schema validation, and helper script tests. Record exact counts and exit codes.

- [x] **Step 3: Build and run Windows**

Use only process-level `TrackFileAccess=false` if reproduced. Build Debug with `dev.windows.json`, run the real backend flow using a process-only test credential, validate login/list/search/detail/logout, PID, window handle, no immediate crash, and normal exit.

- [x] **Step 4: Build and run Android**

Build Debug with `dev.android-emulator.json`, install on `employee_api36`, validate real backend login/list/detail/logout, then record package PID, resumed MainActivity and package-scoped fatal log count.

- [x] **Step 5: Final safety audit**

Run `git diff --check`, review every changed/untracked path, scan names and staged content without printing values, and confirm no env, credential, token, real employee data, build artifact, cache, local.properties or Docker data is staged.

- [x] **Step 6: Create logical commits after all gates pass**

Stage reviewed file sets and create up to four commits:

```text
feat(backend): add authenticated employee directory API
feat(app): add login and employee directory flow
test: validate employee directory vertical slice
docs: document employee directory MVP
```

Combine test files with their feature commit if that preserves a clearer red/green change; do not amend, push, or rebase.

- [x] **Step 7: Post-commit verification**

Confirm clean status, branch `feature/employee-directory-mvp`, preserved `44adc69` and `6102448`, new traceable commits, zero remotes, and no push.

## Plan Self-Review

- Spec coverage: all backend, Flutter, security, migration, real HTTP, Windows, Android, documentation and Git requirements map to Tasks 1-9.
- Placeholder scan: no unresolved placeholder or undefined implementation step remains.
- Type consistency: `Employee.user` uses reverse name `employee_profile`; Flutter authentication consistently uses `AuthSessionStore`, `AuthController`, `TokenStorage`, and the existing `ApiClient`.
- Scope: no write API, HR edit screen, high-sensitivity employee field, external identity source, cache feature, workflow, microservice or unsupported platform is introduced.
