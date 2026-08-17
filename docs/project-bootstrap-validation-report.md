# 企业员工管理系统基础工程验收报告

验收日期：2026-08-17

工作区：`D:\员工管理`

总体状态：`PASSED WITH WARNINGS`

本报告只记录开发工具、命令、产物、进程和协议结果，不记录代理值、密码、Token、签名材料或真实员工数据。

## 1. 验收结论

| 范围 | 状态 | 结论 |
| --- | --- | --- |
| Git 骨架基线 | PASSED | 保留提交 `44adc69 chore: import initial project scaffold`，未 reset、clean、restore 或删除未跟踪文件 |
| Flutter 平台工程 | PASSED | 只生成并保留 Android、Windows；`pubspec.lock` 已纳入版本控制 |
| Flutter 质量门禁 | PASSED | format 28 个文件、analyze 无问题、Flutter 测试 8/8 |
| Windows Debug | PASSED WITH WARNINGS | EXE 实际构建、启动、窗口进程验证和正常退出均通过；构建需要进程级 `TrackFileAccess=false` 绕过本机 MSBuild FileTracker 挂起 |
| Android Debug | PASSED WITH WARNINGS | APK 实际构建并在 `employee_api36` 安装、启动；PID 与前台 Activity 通过 ADB 验证，首次 `am start -W` 等待超时但应用未崩溃 |
| Docker Compose | PASSED | `db`、`redis`、`api` 启动；PostgreSQL 与 Redis healthy，API running |
| PostgreSQL / Redis | PASSED | SQL `SELECT 1` 返回 `1`；Redis CLI 和 Django settings 驱动探针均返回 `PONG` |
| Django | PASSED | check、迁移差异、幂等 migrate、SQLite 与 PostgreSQL 模式 pytest、三个 HTTP 端点全部通过 |
| 统一脚本 | PASSED | `scripts/check.ps1` 最终退出码 0，Compose 配置使用静默校验，不展开环境值 |
| 默认开发环境 | PASSED WITH WARNINGS | 持久用户变量指向 D 盘且代理变量未设置；当前项目生成的 Pub 元数据仍引用 C 盘缓存，按用户要求未重复 `flutter pub get` |

## 2. 实际工具版本

- Flutter 3.47.0 stable，Dart 3.13.0，DevTools 2.60.0。
- Python 3.12.13，Django 5.2.17，pytest 9.1.1，Ruff 0.16.3。
- Docker Engine/Client 29.7.2，Docker Compose 5.3.1。
- Gradle 9.3.1，Android Gradle Plugin 9.1.1，Kotlin 2.4.0，`compileSdk = 37`。
- Android namespace/applicationId：`com.yourcompany.employee_app`，仍为已批准的开发占位符。
- Windows 开发人员模式：`AllowDevelopmentWithoutDevLicense=1`。

## 3. Flutter 与平台产物

### Windows

- 构建命令：`flutter build windows --debug --dart-define-from-file=../../config/dev.windows.json`。
- 产物：`apps/employee_app/build/windows/x64/runner/Debug/employee_app.exe`。
- 大小：983,040 字节。
- SHA-256：`BD2591403D1397F762727EEA56AD1A24F7B5D099FE4DAC31B4CAA78925789DEA`。
- 运行证据：本次启动 PID 8896，窗口句柄非零，进程未立即退出，正常关闭后退出码 0。
- 警告：只在该次构建进程设置 `TrackFileAccess=false`；没有持久修改系统或 Visual Studio 配置。

### Android

- 构建命令：`flutter build apk --debug --dart-define-from-file=../../config/dev.android-emulator.json`。
- 产物：`apps/employee_app/build/app/outputs/flutter-apk/app-debug.apk`。
- 大小：165,290,276 字节。
- SHA-256：`A2B5608187E03C3A82F8162161857421F7D330E99C44DAC2E009402F1CABEC7F`。
- 设备：`employee_api36` / `emulator-5554`，boot completed。
- 安装：`adb install -r` 返回 success。
- 运行证据：包 `com.yourcompany.employee_app`，PID 3354；`topResumedActivity` 与 `ResumedActivity` 均为 `.MainActivity`；本次日志无 `FATAL EXCEPTION`。
- 警告：首次 `am start -W` 在约 12.5 秒超时；随后 PID、前台 Activity 和日志均证明应用正常运行。Android 工具链还输出过不阻断构建的 SDK XML 兼容性提示。

Android 构建使用持久用户 Gradle 目录 `D:\DevCaches\Gradle`，没有隔离进程级 Gradle 目录、人工 Maven 缓存、临时代理变量或离线参数。

## 4. Docker、数据库与 Django

执行 `docker compose -f deploy/docker-compose.dev.yml config --quiet` 和 `up -d --build`。最终状态：

- `db`：running / healthy，PostgreSQL 17 Alpine。
- `redis`：running / healthy，Redis 8 Alpine。
- `api`：running，端口 8000。
- 命名卷保持存在；未执行 `down -v`、reset、prune 或 WSL unregister。

首次 API 构建发现没有有效 `.dockerignore`，BuildKit 上下文为 111.86 MB。增加白名单式 `.dockerignore` 后，缓存命中重建传输上下文为 2.63 kB；镜像审计确认包含 34 个 Python 文件，且不含项目 `.venv`、`.env` 或 `.pyc`。

Django 基础设置原先没有暴露 `REDIS_URL`。按红灯到绿灯流程增加配置契约测试，并加入环境驱动默认值；单项测试先因无法导入设置失败，最小实现后通过。

| 验证 | 状态 | 结果 |
| --- | --- | --- |
| Django check | PASSED | 0 个问题 |
| `makemigrations --check --dry-run` | PASSED | No changes detected |
| `migrate --noinput` | PASSED | No migrations to apply |
| 默认 SQLite pytest | PASSED | 9/9 |
| PostgreSQL 模式 pytest | PASSED | 9/9，vendor 为 `postgresql` |
| `/api/v1/health/` | PASSED | HTTP 200，service/database 均为 `ok` |
| `/api/schema/` | PASSED | HTTP 200，OpenAPI 内容类型 |
| `/api/docs/` | PASSED | HTTP 200，HTML 内容类型 |
| API 启动日志 | PASSED | 检查 18 行，异常模式 0 |

## 5. 统一质量检查

最终命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1
```

提交前复验时间：2026-08-17 10:52:44 至 10:53:08（Asia/Shanghai），24.2 秒，退出码 0。

- Dart format：28 个文件，0 变更。
- Flutter analyze：No issues found。
- Flutter test：8/8。
- Ruff format/check：33 个文件，全部通过。
- Django check：0 个问题。
- pytest：9/9。
- Docker Compose config：静默校验通过。

PowerShell 辅助脚本测试也通过：Python 解释器顺序为项目 venv、`py -3.12`、`python`；Flutter 分析会使用并清理临时 ASCII 联接。

## 6. 环境与遗留警告

持久用户变量仍为：

- `GRADLE_USER_HOME=D:\DevCaches\Gradle`
- `PUB_CACHE=D:\DevCaches\Pub\Cache`
- `ANDROID_HOME=D:\Android\Sdk`
- `ANDROID_AVD_HOME=D:\Android\avd`
- `ANDROID_SDK_ROOT` 未设置

用户级和当前验收进程的 `GRADLE_OPTS`、`JAVA_TOOL_OPTIONS`、`HTTP_PROXY`、`HTTPS_PROXY`、`FLUTTER_STORAGE_BASE_URL` 均为 `UNSET`；没有输出或记录任何代理值。

Codex 宿主进程没有继承重启后写入的四个 D 盘用户变量。当前项目 `.dart_tool/package_config.json` 中 97 个 Pub 包根仍指向 C 盘，并使 C 盘 Pub Cache 被重新创建为 9,877 个文件、154,872,143 字节。该目录和 `.dart_tool` 均未纳入 Git。用户明确要求本轮不重复 `flutter pub get`，因此未重写生成元数据、未删除该缓存；后续如允许，可在真正继承 `PUB_CACHE` 的新终端中单独重新解析依赖。

## 7. Git 与范围控制

- 骨架提交保留为 `44adc69`。
- 没有创建远程仓库、没有 push、没有修改完整登录、CRUD、考勤、审批或权限业务范围。
- 没有提交 `.env`、Token、证书、签名、生产密钥、真实员工数据、构建产物、虚拟环境、缓存或 Docker 数据。
- 最终提交消息为 `chore: complete local project bootstrap`；提交哈希以本报告所在提交的 `git log` 为准。
