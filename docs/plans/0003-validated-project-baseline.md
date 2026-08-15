# Validated Project Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改动业务范围、不泄露本地凭据且不重复配置 SDK 的前提下，补齐真实 Flutter Android/Windows 工程，验证 Django、PostgreSQL、Redis、Docker 与双平台运行，并建立可复核的首个 Git 基线。

**Architecture:** 沿用既有 Flutter feature-first 客户端和 Django 模块化单体，不引入新业务或新平台。先提交经安全审查的静态骨架快照，再由本机 Flutter SDK 补齐标准平台文件；所有成功结论必须同时由命令退出码、实际产物、进程或网络连接证明。

**Tech Stack:** Flutter 3.47 / Dart 3.13、Riverpod、go_router、Dio、Django 5.2、DRF、PostgreSQL 17、Redis 8、Docker Compose、PowerShell、Git。

## Global Constraints

- 只支持 Windows 与 Android，不创建 iOS、Web、macOS 或 Linux 平台目录。
- Flutter 生成器只允许在 `apps/employee_app` 执行，并保护现有 `lib/**` 与 `test/**`。
- 后端只使用 `backend/.venv/Scripts/python.exe`，不向全局 Python 安装依赖。
- 不删除 Docker volume，不执行 Git reset/clean/restore，不覆盖用户数据。
- 不把 `.env`、凭据、签名、构建产物、缓存、虚拟环境或本地数据库加入 Git。
- Android applicationId/namespace 暂保留已记录的开发占位符 `com.yourcompany.employee_app`。
- 只创建本地提交，不创建远程仓库，不 push。

---

### Task 1: 安全边界与骨架快照

**Files:**
- Modify: `.gitignore`
- Create: `docs/plans/0003-validated-project-baseline.md`
- Verify: all current repository files excluding ignored runtime data

**Interfaces:**
- Produces: 后续 Flutter 生成前可回退、无敏感信息的 Git 骨架提交。

- [ ] **Step 1: 验证新增忽略规则**

  对 `.env`、虚拟环境、Flutter 构建、Android 本地配置、仓库内 Docker/PostgreSQL/Redis 数据目录与临时文件执行 `git check-ignore`；同时确认 migrations 和 `pubspec.lock` 不被忽略。

- [ ] **Step 2: 验证现有后端骨架**

  在 `backend` 使用 `.venv/Scripts/python.exe` 运行 Ruff format/check、`manage.py check --settings=config.settings.test` 和 pytest，记录真实测试数量。

- [ ] **Step 3: 审查提交候选**

  使用 `git status --porcelain=v1 --untracked-files=all`、文件大小审查和只输出变量名的敏感扫描，确认无 `.env`、缓存、构建产物、密钥、签名或本地数据。

- [ ] **Step 4: 建立骨架快照**

  显式暂存 `.editorconfig`、`.env.example`、`.github`、`.gitignore`、`AGENTS.md`、`CONTRIBUTING.md`、`README.md`、`apps`、`backend`、`config`、`deploy`、`docs`、`scripts`；审查 cached stat/name/status 与敏感文件名后提交 `chore: import initial project scaffold`。

### Task 2: Flutter 平台工程补全与依赖锁定

**Files:**
- Preserve: `apps/employee_app/lib/**`, `apps/employee_app/test/**`, `apps/employee_app/integration_test/**`
- Modify/Create: `apps/employee_app/android/**`, `apps/employee_app/windows/**`
- Create: `apps/employee_app/pubspec.lock`
- Verify/Modify if generator assumptions remain: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: 可直接构建的 Android/Windows Flutter 项目和真实依赖锁文件。

- [ ] **Step 1: 建立源码哈希基线**

  记录 `lib/**`、`test/**`、`integration_test/**` 和 `pubspec.yaml` 每个文件的 SHA-256 及平台目录清单；快照提交作为内容回退点。

- [ ] **Step 2: 运行受限 Flutter 生成器**

  在 `apps/employee_app` 执行 `flutter create --platforms=android,windows --org com.yourcompany --project-name employee_app .`；确认只存在 `android` 和 `windows` 平台目录。

- [ ] **Step 3: 复核生成差异**

  对比哈希与 Git diff，确认生成器没有改变既有 Dart 业务语义；保留 Debug 专用 Android Network Security Configuration 和中文应用标题，拒绝 Release 明文 HTTP 或签名配置。

- [ ] **Step 4: 锁定依赖**

  执行 `flutter pub get`，确认 `pubspec.lock` 存在且 `flutter_riverpod`、`go_router`、`dio` 被解析；CI 构建不得再依赖临时 `flutter create` 来掩盖缺失的平台文件。

### Task 3: Flutter 静态质量与双平台构建

**Files:**
- Modify only if formatting requires it: `apps/employee_app/**/*.dart`
- Produce (ignored): `apps/employee_app/build/windows/x64/runner/Debug/**`
- Produce (ignored): `apps/employee_app/build/app/outputs/flutter-apk/app-debug.apk`

**Interfaces:**
- Produces: 通过格式、分析、测试的 Dart 工程，以及可启动的 Windows EXE 和 Android APK。

- [ ] **Step 1: 执行格式检查**

  运行 `dart format --output=none --set-exit-if-changed .`；若失败，先列出受影响文件，再执行 `dart format .` 并重跑检查。

- [ ] **Step 2: 执行分析和测试**

  运行 `flutter analyze` 与 `flutter test`，记录测试数量；失败时按根因做最小修复，不删除或跳过测试。

- [ ] **Step 3: 构建 Windows Debug**

  运行 `flutter build windows --debug --dart-define-from-file=../../config/dev.windows.json`，确认 EXE 和所需 DLL/数据目录真实存在并记录大小。

- [ ] **Step 4: 构建 Android Debug**

  运行 `flutter build apk --debug --dart-define-from-file=../../config/dev.android-emulator.json`，确认 APK 真实存在并记录大小、包名和入口 Activity。

### Task 4: Windows 与 Android 真实运行验收

**Files:**
- Verify only: Windows Debug bundle and Android Debug APK

**Interfaces:**
- Produces: Windows 窗口进程证据、Android 应用进程与前台 Activity 证据。

- [ ] **Step 1: 验证 Windows 应用**

  启动实际 Debug EXE，条件轮询进程与非零窗口句柄，确认未立即退出且无阻塞性启动错误，再正常关闭本次启动的进程。

- [ ] **Step 2: 验证模拟器**

  通过 `flutter devices`、`adb devices` 确认 `employee_api36` 对应设备；仅在未运行时启动该 AVD，并等待 Android boot completed。

- [ ] **Step 3: 安装并启动项目 APK**

  清空本次 logcat 缓冲，使用 `adb install -r` 安装 APK并显式启动 `com.yourcompany.employee_app/.MainActivity`。

- [ ] **Step 4: 验证 Android 运行状态**

  使用 `pidof`、`dumpsys activity/window` 确认应用进程和前台 Activity，检查本次启动日志无该包相关 `FATAL EXCEPTION` 或崩溃。

### Task 5: Docker、PostgreSQL、Redis 与 Django 联通

**Files:**
- Modify if required by a failing contract: `backend/config/settings/base.py`
- Test if settings contract changes: `backend/tests/test_database_settings.py`
- Local ignored file if needed: `.env`
- Verify: `deploy/docker-compose.dev.yml`

**Interfaces:**
- Consumes: `POSTGRES_*` 与 `REDIS_URL` 开发配置。
- Produces: 健康的 `db`/`redis`/`api` 服务、真实 SQL/PING 结果和 Django PostgreSQL vendor 证明。

- [ ] **Step 1: 解析并启动 Compose**

  运行 `docker compose -f deploy/docker-compose.dev.yml config --quiet` 和 `up -d`，条件轮询直到 db、redis 健康且 api 运行；不删除或重建命名卷。

- [ ] **Step 2: 验证数据库与缓存协议**

  在容器内执行 PostgreSQL `SELECT 1` 并确认目标数据库存在；执行 Redis `PING` 并确认 `PONG`。

- [ ] **Step 3: 验证 Django 配置契约**

  若现有 Django settings 未暴露 `REDIS_URL`，先写失败测试，再最小加入环境驱动设置；通过 Django shell 使用 settings 中的 PostgreSQL/Redis 主机配置完成连接，输出只记录 vendor、数据库名分类和协议结果，不记录凭据。

- [ ] **Step 4: 执行迁移与后端测试**

  使用项目 venv 运行 `manage.py check`、`makemigrations --check --dry-run`、`migrate`、PostgreSQL 模式 pytest；如执行 `manage.py test` 发现 0 个测试，必须如实记录为 0 而非“测试通过”。

- [ ] **Step 5: 验证 Django 服务**

  确认 api 进程与 8000 端口，真实请求 `/api/v1/health/`、`/api/schema/`、`/api/docs/`，检查状态码、数据库 vendor 与日志中无启动异常。

### Task 6: 统一质量检查

**Files:**
- Modify only if a script defect is reproduced: `scripts/check.ps1`

**Interfaces:**
- Produces: 从仓库根目录可重复执行且退出码为 0 的全量静态/单元/Compose 配置检查。

- [ ] **Step 1: 执行统一脚本**

  记录开始/结束时间，在仓库根运行 `powershell -ExecutionPolicy Bypass -File .\scripts\check.ps1`，保留每个子步骤与最终退出码。

- [ ] **Step 2: 处理脚本或项目失败**

  若失败，先区分项目错误与脚本错误；仅做最小修复并完整重跑，不跳过步骤或强制返回 0。

### Task 7: 验收报告与正式基线提交

**Files:**
- Create: `docs/project-bootstrap-validation-report.md`
- Modify: `docs/plans/0003-validated-project-baseline.md`
- Modify if verified status changed: `docs/environment-report.md`, `docs/environment-setup-state.md`

**Interfaces:**
- Produces: 命令、产物、运行、数据库、风险和 Git 结果均可追溯的最终报告与干净工作区。

- [ ] **Step 1: 汇总真实结果**

  报告环境、Flutter、Windows、Android、Docker、PostgreSQL、Redis、Django、统一检查、文件变更、Git 提交与遗留风险；每项只能为 `PASSED`、`PASSED WITH WARNINGS`、`FAILED` 或 `BLOCKED`。

- [ ] **Step 2: 最终安全扫描**

  审查 `git status`、diff、生成文件大小与敏感变量名，确认暂存区无 `.env`、凭据、签名、缓存、构建产物、虚拟环境、Docker/数据库数据或个人配置。

- [ ] **Step 3: 创建验证提交**

  显式暂存已审查的生成文件、最小修复和报告；检查 cached stat/name/status 后提交 `chore: complete local project bootstrap`。

- [ ] **Step 4: 提交后复核**

  运行 `git status --short` 与 `git log --oneline --decorate -n 5`，目标是工作区干净、两次本地提交存在且没有远程/push 操作。

## Plan Self-Review

- 规范覆盖：Phase 1 的十五项问题、Git 双提交、Flutter 生成/锁定/双平台运行、ADB、Compose、PostgreSQL、Redis、Django、统一检查和最终报告都有对应任务。
- 占位符检查：计划不含待定实现；正式产品 applicationId 是既有明确未决项，本轮只保留已批准的开发占位符。
- 接口一致性：Flutter 配置继续来自 Dart define JSON；Django 数据库和 Redis 继续来自环境；未引入新平台、微服务或业务功能。
