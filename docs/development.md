# 开发指南

## 环境

使用 Python 3.12、Django 5.2.x 与 Flutter stable。Flutter 的准确版本必须以本机成功执行 `flutter --version` 的结果为准；当前仓库约束见 `pubspec.yaml`，不得凭空填写版本。首次启动优先运行 `scripts/bootstrap.ps1`。本地 `.env` 只允许开发值，不得用于生产。

## 日常流程

1. 从最新 `main` 创建 `feature/...`、`fix/...` 或 `chore/...` 分支。
2. 复杂任务先更新 `docs/plans/`；架构变化更新 ADR。
3. 行为变化先写失败测试，再实现最小代码。
4. 执行 `scripts/check.ps1`，并分别验证 Windows 与 Android。
5. 创建 PR，记录每条验证结果和未运行原因。

## 后端

默认测试使用 SQLite，以获得快速且无外部依赖的反馈：

```powershell
cd backend
.\.venv\Scripts\python.exe -m pytest
```

PostgreSQL 集成测试使用同一套迁移、User、Health API 和数据库测试。先启动开发数据库，再从本地 `.env` 或当前进程环境提供 `POSTGRES_*`，并显式选择 PostgreSQL：

```powershell
$env:TEST_DATABASE_ENGINE = "postgresql"
$env:EXPECTED_DATABASE_VENDOR = "postgresql"
.\.venv\Scripts\python.exe -m pytest
```

`config.settings.test` 只从环境变量读取 PostgreSQL 数据库名、用户、密码、主机和端口；不要把数据库密码写入源码或文档。GitHub Actions backend job 设置相同模式，因此已启动的 PostgreSQL service 会被测试实际使用。

PostgreSQL/Redis 全量模式通过 `scripts/check.ps1` 的 one-off 容器运行，Redis 使用隔离测试 DB。不要把测试数据库、Redis 数据、Mailpit 邮件或任何凭据加入缓存/产物。

## 账号安全与本地邮件

- `User.username` 是稳定账号标识；登录请求使用 `identifier`，可传用户名或大小写不敏感的账号邮箱。
- `User.email` 用于登录、邀请和恢复，和目录字段 `Employee.work_email` 分开维护；两者不一致时管理界面提示，但不自动同步。
- 密码至少 12 个字符，并复用 Django common/numeric/similarity validators。后端是最终权威。
- 邀请默认 48 小时、重置码默认 30 分钟；数据库只保存摘要，普通 API 和日志不返回一次性码。

启动本地邮件捕获：

```powershell
docker compose -f .\deploy\docker-compose.dev.yml up -d --build
```

Mailpit UI 为 `http://127.0.0.1:8025`，只允许 `.invalid` 虚构收件人。生产设置必须显式配置邮件后端、主机、端口和发件人，不默认回退 Mailpit。

开发服务器监听 `0.0.0.0:8000` 仅用于受信任局域网。

## 演示账号与目录数据

`seed_demo_data` 幂等创建 4 个部门、6 个岗位、12 名虚构员工和三类 Group，并调用与部署相同的 RBAC 同步服务。密码必须来自当前进程 `EMPLOYEE_DEMO_PASSWORD`，命令不会输出该值：

```powershell
$securePassword = Read-Host "演示账号密码" -AsSecureString
$env:EMPLOYEE_DEMO_PASSWORD = [System.Net.NetworkCredential]::new("", $securePassword).Password
try {
  .\.venv\Scripts\python.exe manage.py seed_demo_data
} finally {
  Remove-Item Env:EMPLOYEE_DEMO_PASSWORD -ErrorAction SilentlyContinue
}
```

开发登录名为 `demo.employee`。`employee` 只读；`hr_admin` 与 `system_admin` 可维护 Department、Position、Employee，执行状态 action 并读取审计。Django Admin 仍要求 `is_staff` 或超级用户。

迁移后或权限定义变化时幂等同步 RBAC：

```powershell
cd backend
.\.venv\Scripts\python.exe manage.py sync_rbac
```

该命令只补充所需权限，不清除额外权限。目录对象没有 DELETE API；不要使用数据库命令绕过 service 的事务、状态规则和审计。

## Flutter 配置

- Windows：`config/dev.windows.json`
- Android 模拟器：`config/dev.android-emulator.json`
- Android 真机：从 `config/dev.android-device.example.json` 复制并填写局域网 IP

配置通过 `--dart-define-from-file` 注入。不要在 Dart 文件中写真实环境地址或敏感值。

Android 的本地 HTTP 只由 `android/app/src/debug/AndroidManifest.xml` 引用 Debug 专用 Network Security Configuration。它支持模拟器访问 `http://10.0.2.2:8000/api/v1`；不得通过该通道传输登录凭据、Token 或敏感员工数据。Staging 与 Production 必须使用 HTTPS，Release 主清单不得开启明文 HTTP。

## 平台生成文件

Android、Windows 平台工程和依赖锁文件已经生成并提交。日常开发不得重复运行 `flutter create`；仅在明确需要重新生成平台文件时执行：

```powershell
cd apps\employee_app
flutter create --platforms=android,windows --org com.yourcompany --project-name employee_app .
flutter pub get
```

执行前后都要审查工作区，确认命令没有新增 iOS、Web、macOS 或 Linux 目录，也没有覆盖业务实现。

## 本机已知兼容项

- Flutter 3.47 在中文工作区可能误算 LSP Content-Length。使用 `scripts/check.ps1`；其中的 `flutter-analysis.ps1` 会创建、验证并删除临时 ASCII junction。
- Windows CMake/MSBuild 无 CPU 进展时，只在当前构建进程设置 `TrackFileAccess=false`，不要持久修改 Visual Studio 或系统配置。
- 新 PowerShell 应从真实用户环境继承 `GRADLE_USER_HOME=D:\DevCaches\Gradle` 与 `PUB_CACHE=D:\DevCaches\Pub\Cache`。不要使用隔离 Gradle 目录、人工 Maven 缓存、临时代理或 `--offline` 绕过构建。
- Android aapt 36 无法直接读取中文路径 APK 时，Flutter 会回退源 Manifest；必须继续用 ADB 安装、PID、前台 Activity 和包级 FATAL 日志确认真实结果。
