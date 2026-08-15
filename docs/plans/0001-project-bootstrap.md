# 企业员工管理系统基础框架 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立仅支持 Windows 与 Android、具备 Django Health API 和 Flutter 健康状态展示的可协作基础工程。

**Architecture:** Flutter 使用 feature-first、Riverpod、go_router 和 Dio；Django 使用模块化单体与分层 settings。PostgreSQL 提供持久化，Redis 只预留，配置通过环境变量与 `--dart-define-from-file` 注入。

**Tech Stack:** Flutter/Dart、Material 3、Riverpod、go_router、Dio、Python 3.12、Django 5.2、Django REST Framework、PostgreSQL、Redis、Docker Compose、pytest、Ruff。

## Global Constraints

- 当前只支持 Windows 与 Android；不得创建 iOS、Web、macOS 或 Linux 平台目录。
- 代码标识符使用英文；界面与主要文档使用简体中文。
- 不实现登录、员工 CRUD、考勤、审批、权限等完整业务。
- 不写入真实密钥、域名、Token、员工数据或正式签名。
- 不覆盖已有 `.env`，不安装全局软件，不创建 Git commit。
- 每个验证命令只记录 `PASSED`、`FAILED` 或 `NOT RUN`。

---

## 2026-08-14 本轮：真实工具链验证补全

**Goal:** 在不增加业务功能、不覆盖既有源码的前提下，把静态骨架推进为可由真实 Flutter、Android、Windows、Docker 与 PostgreSQL 工具链复验的构建基线，并如实保留当前环境无法执行的项目。

**Architecture:** 继续保持 Flutter feature-first 与 Django 模块化单体。Flutter 平台目录仅由当前 Flutter SDK 补齐 Android/Windows 标准生成文件；开发期 Android 明文 HTTP 只通过 `src/debug` 的 Network Security Configuration 放行。Django 快速测试可使用 SQLite，但 PostgreSQL 集成模式完全由环境变量启用，CI 后端作业必须真实使用 PostgreSQL 服务。

**Tech Stack:** 当前实际可发现的 Git 2.45.1、Android SDK、Visual Studio 2022、仓库内 Python 3.12 虚拟环境；待发现或由开发者提供的 Flutter/Dart 与 Docker Desktop；Django 5.2、PostgreSQL 17、Redis 8、PowerShell 5.1。

### 本轮全局约束

- 只保留 Android 与 Windows，不创建 iOS、Web、macOS 或 Linux。
- 保留现有 `lib`、`test`、`backend`、`docs`、`scripts`、CI 与配置；不删除整个项目或用生成器覆盖业务源码。
- 不实现登录、员工、部门、考勤、审批、公告或权限等完整业务。
- 不修改全局 PATH、ExecutionPolicy 或 Git 配置，不安装全局软件。
- 不生成 Release 签名、证书、真实密钥、Token 或真实员工数据。
- 不创建 Git commit；每条验收命令只报告 `PASSED`、`FAILED` 或 `NOT RUN`。

### 本轮环境探测基线

- `git --version`：`PASSED`，Git 2.45.1.windows.1。
- `flutter --version`、`dart --version`、`flutter doctor -v`、`flutter devices`：`FAILED`，命令不在 PATH；常见 Flutter SDK 路径未发现。
- `python --version`、`py -3.12 --version`：`FAILED`，命令不在 PATH；仓库现有 `backend/.venv/Scripts/python.exe` 可继续用于后端验证。
- `docker --version`、`docker compose version`、`docker info`：`FAILED`，命令不在 PATH；常见 Docker Desktop CLI 路径未发现。
- Android SDK 的 `adb.exe` 与 `emulator.exe` 位于用户本地 SDK；后续继续检查 AVD、设备和构建工具。
- 仓库为无提交的 `main`，所有文件当前未跟踪，因此执行生成器前后需使用文件清单与哈希保护现有 `lib`/`test`，不能只依赖 `git diff`。

### Task 9：精确环境报告与平台完整性审计

**Files:**
- Modify: `docs/environment-report.md`
- Inspect: `apps/employee_app/android/**`, `apps/employee_app/windows/**`

**Interfaces:**
- Produces: 后续命令使用的实际工具绝对路径、版本、设备清单与明确阻塞项。

- [x] 逐条隔离执行附件列出的十条环境命令并记录退出状态与版本。
- [x] 检查 Android SDK、AVD、JDK、Visual Studio C++ 和常见 Flutter/Docker 安装位置，不修改全局环境变量。
- [x] 对 `lib` 与 `test` 建立文件清单和 SHA-256 基线，并审计 Android/Windows 缺失的标准生成文件。
- [x] 把个人路径归一为工具类别后更新环境报告，敏感值不得写入文档。

### Task 10：Flutter 双平台生成、依赖锁定与 Debug 网络边界

**Files:**
- Preserve: `apps/employee_app/lib/**`, `apps/employee_app/test/**`
- Modify/Create with Flutter SDK: `apps/employee_app/android/**`, `apps/employee_app/windows/**`, `apps/employee_app/pubspec.lock`
- Modify: `apps/employee_app/android/app/src/debug/AndroidManifest.xml`
- Create: `apps/employee_app/android/app/src/debug/res/xml/network_security_config.xml`
- Modify: `docs/development.md`, `docs/security-baseline.md`

**Interfaces:**
- Consumes: `AppConfig.fromEnvironment()` 与 `config/dev.*.json`。
- Produces: `com.yourcompany.employee_app` 的 Android Debug APK、Windows Debug 目录，以及仅 Debug 可访问本地 HTTP 的网络策略。

- [ ] Flutter 可用时先记录现有源码哈希，再执行 `flutter create . --platforms=android,windows --org com.yourcompany --project-name employee_app`。
- [ ] 确认生成器未创建额外平台、未改变 `lib`/`test` 语义，并保留中文应用名与占位 applicationId 未决项。
- [ ] 执行 `flutter pub get` 生成真实 lockfile，再运行 `flutter pub outdated`；只在真实兼容冲突时调整依赖。
- [x] 审计旧 Debug 清单只有宽泛 cleartext 开关后，改用 `src/debug` 专用 Network Security Configuration；XML 解析验证主清单未启用 cleartext。
- [ ] 运行 Dart 格式检查、Flutter analyze/test、Windows Debug 与 Android Debug 构建，并记录产物绝对路径。

### Task 11：PostgreSQL 测试模式、Docker 联通与 API 证明

**Files:**
- Modify: `backend/config/settings/test.py`
- Modify/Test: `backend/tests/test_health_api.py` 或新增聚焦数据库后端契约的测试
- Modify: `.github/workflows/ci.yml`, `docs/development.md`, `docs/environment-report.md`
- Verify: `deploy/docker-compose.dev.yml`

**Interfaces:**
- Consumes: `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`, `POSTGRES_PORT` 与显式测试数据库模式变量。
- Produces: SQLite 快速测试和 PostgreSQL 集成测试两条可区分路径；CI 的 backend job 在 PostgreSQL 上运行同一套迁移、用户与 API 测试。

- [x] 先写数据库模式行为测试并确认其因尚未支持 PostgreSQL 测试配置而失败。
- [x] 最小实现环境变量驱动的 PostgreSQL test settings，同时保留无 Docker 的 SQLite 快速模式。
- [x] 调整 CI backend 环境变量，使已启动的 PostgreSQL service 被 pytest 实际使用；本地 YAML 与配置测试通过，远程状态仍为未运行。
- [ ] Docker 可用时执行 compose config/up/ps，不删除卷；等待 db/redis healthy，迁移后启动 API。
- [ ] 通过 health 响应和 Django 连接 vendor 双重确认真实 PostgreSQL，再请求 health/schema/docs。

### Task 12：PowerShell 入口与文档命令一致性

**Files:**
- Modify: `scripts/bootstrap.ps1`, `scripts/run-backend.ps1`, `scripts/check.ps1`
- Verify/Modify if required: `scripts/run-flutter-windows.ps1`, `scripts/run-flutter-android.ps1`
- Modify: `README.md`, `docs/development.md`

**Interfaces:**
- Produces: Python 解析顺序 `backend/.venv/Scripts/python.exe` -> `py -3.12` -> `python`，且不依赖全局 Python PATH。

- [x] 先用受控 PATH/可用 venv 运行脚本，捕获当前 Python 解析或检查链缺陷。
- [x] 抽取并测试一致的 Python 调用策略，保留 `$ErrorActionPreference = "Stop"` 与外部命令退出码检查。
- [x] 让 `check.ps1` 串联 Dart format、Flutter analyze/test、Ruff format/lint、Django check、pytest 和 Compose config；完整运行仍受缺失 Flutter/Docker 阻塞。
- [x] README 所有脚本示例统一为 `powershell -ExecutionPolicy Bypass -File .\\scripts\\xxx.ps1`，脚本本身不修改全局 ExecutionPolicy。

### Task 13：设备联调、安全审计与最终验收

**Files:**
- Modify: `docs/environment-report.md`, `docs/plans/0001-project-bootstrap.md`

**Interfaces:**
- Produces: 可复核的命令状态、客户端失败/重试恢复证据和最终工作区差异清单。

- [ ] Windows 构建可用时启动应用，确认环境、API 地址和响应式壳层显示。
- [ ] AVD 与 Flutter 可用时验证后端关闭时友好失败、恢复后点击重试成功，且无崩溃或敏感日志。
- [ ] 执行附件列出的后端、Flutter、Docker 与脚本最终验收命令；缺失工具导致的项目标为 `NOT RUN`，不得推断成功。
- [ ] 确认无额外平台、Release 签名、密钥、员工真实数据或越界业务。
- [ ] 最后输出 `git status --short` 与 `git diff --stat`，不创建 commit。

### 本轮计划自审

- 规范覆盖：环境、Flutter 生成/锁定、Android Debug 网络、双平台构建、模拟器恢复、Docker/PostgreSQL、CI、PowerShell、安全与最终十五节报告均有对应任务。
- 占位符检查：计划没有 `TBD`、`TODO` 或未定义的实现步骤；实际版本和状态只由命令输出更新。
- 一致性检查：Flutter 继续通过 Dart define JSON 使用两个开发 API 地址；PostgreSQL 测试配置只接受环境变量；Python 解析优先级在脚本和文档中保持一致。

---

## 上一轮初始环境结论（历史记录）

本节保留第一次搭建时的环境记录；本轮准确状态以 `docs/environment-report.md` 和上方“本轮环境探测基线”为准。

- 工作区为空，不是 Git 仓库。
- Git 2.45.1 可用。
- 项目可访问的 Python 为 3.12.13；系统 `python` 命令不在 PATH。
- Visual Studio Professional 2022 17.14.21 与 C++ 工具链可用。
- Flutter、Dart、Android SDK 和 Docker 不可用。
- 因此后端可实际安装和验证；Flutter 与 Docker 只搭建并静态审查，相关构建命令标记 `NOT RUN`。

## 假设

- 当前目录就是仓库根目录，不增加 `employee-management/` 外层。
- `com.yourcompany` 仅为开发期占位符。
- 测试设置默认使用 SQLite，使单元测试不依赖正在运行的 PostgreSQL；开发与生产仍使用 PostgreSQL。
- 开发 API 文档默认开放，生产环境必须显式设置开关。
- 用户提供的完整任务说明视为已批准设计。

## 目录结构

- `apps/employee_app/`：Flutter 应用、Android/Windows runner、单元与 Widget 测试。
- `backend/`：Django 配置、模块、迁移与 pytest 测试。
- `config/`：Flutter 编译期环境配置。
- `deploy/`：PostgreSQL、Redis 与 API 开发容器。
- `docs/`：架构、API、安全、开发、ADR、环境报告和未决事项。
- `scripts/`：PowerShell 初始化、运行和检查入口。
- `.github/`：CI 与 PR 模板。

## Task 1：仓库与环境基线

**Files:**
- Create: `.gitignore`, `.editorconfig`, `.env.example`, `docs/environment-report.md`

**Interfaces:**
- Produces: 后续脚本使用的环境变量名称与可信环境状态记录。

- [x] 初始化 Git 仓库但不提交。
- [x] 写入忽略规则、编码规则和仅用于开发的环境示例。
- [x] 记录每条环境检查命令的真实状态，不记录个人路径。
- [x] 验证 `git status --short` 不包含 `.env`、虚拟环境或密钥文件。

## Task 2：先写后端失败测试

**Files:**
- Create: `backend/tests/test_user_model.py`
- Create: `backend/tests/test_health_api.py`
- Create: `backend/tests/test_schema.py`
- Create: `backend/tests/test_cors_settings.py`

**Interfaces:**
- Consumes: `modules.accounts.User`, `/api/v1/health/`, `/api/schema/`。
- Produces: 自定义用户、健康检查、schema 与 CORS 的验收契约。

- [x] 写入 UUID 用户模型测试：`User.objects.create_user(username="test_user")` 的主键必须为 UUID，且时间字段存在。
- [x] 写入健康接口测试：数据库正常时断言 200 与固定公开字段；模拟游标异常时断言 503 且无异常细节。
- [x] 写入 schema 生成测试，断言响应包含 `/api/v1/health/`。
- [x] 写入 development CORS 测试，断言配置来自环境列表。
- [x] 在实现前运行目标测试，确认因 `config` 尚不存在而失败。

## Task 3：最小 Django 实现

**Files:**
- Create: `backend/manage.py`, `backend/config/**`, `backend/modules/**`, `backend/requirements/**`, `backend/pyproject.toml`, `backend/pytest.ini`

**Interfaces:**
- Produces: `modules.accounts.User`；`HealthView.get(request) -> Response`；Django settings 模块。

- [x] 创建分层 settings；base 只含公共配置，development/test/production 覆盖环境差异。
- [x] 创建 UUID 自定义 User 与首个迁移，并设置 `AUTH_USER_MODEL = "accounts.User"`。
- [x] 创建轻量 health API、统一异常骨架、schema 与 docs 路由。
- [x] 安装项目虚拟环境依赖，运行迁移、Ruff、Django check 与 pytest。
- [x] 只修复实现问题，不删除或跳过有效测试。

## Task 4：先写 Flutter 失败测试

**Files:**
- Create: `apps/employee_app/test/core/config/app_config_test.dart`
- Create: `apps/employee_app/test/features/health/health_repository_test.dart`
- Create: `apps/employee_app/test/features/dashboard/dashboard_page_test.dart`
- Create: `apps/employee_app/test/features/shell/adaptive_shell_test.dart`
- Create: `apps/employee_app/test/app_smoke_test.dart`

**Interfaces:**
- Consumes: `AppConfig`, `HealthRepository`, `DashboardPage`, `AdaptiveShell`, `EmployeeApp`。
- Produces: Flutter 配置、网络边界、响应式壳层与启动行为契约。

- [x] AppConfig 测试显式传入环境和 URL，断言解析与默认值。
- [x] 使用 mocktail 隔离 API Client 测试 repository，不访问网络。
- [x] 注入 Riverpod override，测试健康状态页面与启动行为。
- [x] 分别以 800 与 1200 像素宽度断言 NavigationBar 与 NavigationRail。
- [ ] 运行测试；当前 Flutter 缺失时记录 `NOT RUN`，不得伪造失败输出。

## Task 5：最小 Flutter 实现与平台骨架

**Files:**
- Create: `apps/employee_app/pubspec.yaml`, `analysis_options.yaml`, `lib/**`, `android/**`, `windows/**`, `integration_test/**`

**Interfaces:**
- Produces: `AppConfig.fromEnvironment()`；`HealthRepository.fetchHealth()`；`healthControllerProvider`；六个路由目的地。

- [x] 实现 AppConfig、Dio client、endpoint、统一异常与 Failure。
- [x] 实现 Health DTO、repository 和 Riverpod FutureProvider，网络错误转换为中文失败状态。
- [x] 实现 Material 3 主题、go_router、六入口响应式 shell 与工作台健康卡。
- [x] 封装 secure storage 与 device service，不从 Widget 直接访问平台服务。
- [x] 写入只包含 Android/Windows 的 runner 骨架和中文显示名称，不配置 release 签名。
- [ ] Flutter 可用后运行 `flutter pub get` 生成真实 `pubspec.lock`；当前环境缺失则保留为明确未完成项。

## Task 6：基础设施、脚本与 CI

**Files:**
- Create: `deploy/docker-compose.dev.yml`, `deploy/backend/Dockerfile*`, `scripts/*.ps1`, `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: 根 `.env`、backend requirements、Flutter config JSON。
- Produces: 一键初始化、运行、检查与四个独立 CI jobs。

- [x] Compose 配置 db、redis、api、命名卷与 healthcheck；API 等待健康 db 后迁移并监听 8000。
- [x] 所有 PowerShell 脚本设置 `$ErrorActionPreference = "Stop"` 并检查外部命令退出码。
- [x] bootstrap 只在 `.env` 不存在时复制开发示例，不删除卷或用户数据。
- [x] CI 分为 backend、flutter analyze/test、Android debug build、Windows debug build。
- [ ] Docker 缺失时将 compose 验证与启动记录为 `NOT RUN`。

## Task 7：协作文档与架构决策

**Files:**
- Create: `README.md`, `AGENTS.md`, `apps/employee_app/AGENTS.md`, `backend/AGENTS.md`, `CONTRIBUTING.md`, `.github/pull_request_template.md`, `docs/*.md`, `docs/decisions/*.md`

**Interfaces:**
- Produces: 两名开发者可直接遵循的启动、测试、安全和协作说明。

- [x] README 覆盖平台、技术栈、启动、测试、真机网络、常见问题、敏感文件与下一步。
- [x] 三份 AGENTS.md 说明范围、验证、安全、API/ADR 同步规则。
- [x] architecture 使用 Mermaid；ADR 记录模块化单体和 Windows/Android first。
- [x] OPEN_DECISIONS 列出十项发布前决策，明确应用标识必须替换。
- [x] 不创建 CODEOWNERS。

## Task 8：最终验证与报告

**Files:**
- Modify: `docs/plans/0001-project-bootstrap.md`（完成状态）

**Interfaces:**
- Produces: 可追溯的 PASSED/FAILED/NOT RUN 命令清单。

- [x] 运行 Ruff format/check、Django check 与 pytest。
- [ ] 在工具可用时运行 Dart format、Flutter analyze/test 与 Windows/Android debug build。
- [ ] 在 Docker 可用时运行 compose config、up、ps 并请求三个 API。
- [x] 检查只存在 Android/Windows 平台目录，无敏感文件、真实员工数据或越界业务。
- [x] 输出 `git status --short` 与 `git diff --stat`，不创建 commit。

## 风险

- 手工 runner 骨架只能在安装匹配版本 Flutter 后通过 `flutter create --platforms=android,windows .` 安全补齐或校验；执行前必须保护业务源码。
- 未生成 `pubspec.lock` 会使 Flutter 依赖解析在首次 `flutter pub get` 时变化。
- Docker 不可用时无法证明 PostgreSQL/Redis 容器实际启动，也无法执行真实 PostgreSQL 连通测试。
- Android SDK 缺失时无法验证 Gradle 与 APK 构建。

## 未决事项

正式应用名称、Android applicationId、API 域名、登录标识、外网访问、Android 分发、Windows 安装包、AD/LDAP、考勤方式与敏感字段范围统一记录在 `docs/OPEN_DECISIONS.md`，不在本次实现中擅自决定。

## 完成状态清单

- [x] 仓库、文档、脚本、CI 与基础设施文件齐全。
- [x] Django 后端与自动测试通过。
- [x] Flutter 源码与测试齐全，仅含 Android/Windows。
- [x] 所有已执行与未执行命令均如实记录。
- [x] 不包含密钥、真实员工数据、正式签名或超范围业务。
