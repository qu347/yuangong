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

开发服务器监听 `0.0.0.0:8000` 仅用于受信任局域网。

## Flutter 配置

- Windows：`config/dev.windows.json`
- Android 模拟器：`config/dev.android-emulator.json`
- Android 真机：从 `config/dev.android-device.example.json` 复制并填写局域网 IP

配置通过 `--dart-define-from-file` 注入。不要在 Dart 文件中写真实环境地址或敏感值。

Android 的本地 HTTP 只由 `android/app/src/debug/AndroidManifest.xml` 引用 Debug 专用 Network Security Configuration。它支持模拟器访问 `http://10.0.2.2:8000/api/v1`；不得通过该通道传输登录凭据、Token 或敏感员工数据。Staging 与 Production 必须使用 HTTPS，Release 主清单不得开启明文 HTTP。

## 平台生成文件

仓库创建环境缺少 Flutter。安装指定 SDK 后执行：

```powershell
cd apps\employee_app
flutter create --platforms=android,windows --org com.yourcompany --project-name employee_app .
flutter pub get
```

确认命令没有新增 iOS、Web、macOS 或 Linux 目录，并审查平台文件差异。
