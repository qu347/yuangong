# 企业员工管理系统

面向企业内部员工的 Windows 与 Android 管理客户端。本仓库已实现第一期“身份认证与员工目录”最小纵向切片，不包含完整人力资源管理业务。

## 平台范围

当前支持：

- Windows 桌面端
- Android 手机端（模拟器与真机）

当前不支持：iOS、macOS、Web、Linux。iOS 仅作为未来可能扩展，不在当前工程中创建或构建。

## 技术栈

- 客户端：Flutter stable、Dart、Material 3、Riverpod、go_router、Dio、flutter_secure_storage
- 后端：Python 3.12、Django 5.2.x、Django REST Framework、SimpleJWT、drf-spectacular、pytest、Ruff
- 基础设施：PostgreSQL 17、Redis 8（预留）、Docker Compose
- 协作：GitHub Actions、Pull Request 模板、ADR

## 第一期功能

- JWT 登录、刷新、当前用户和退出登录。
- 只读部门、岗位和员工目录。
- 员工姓名/工号/工作邮箱搜索，部门和在职状态筛选，受限分页与排序。
- Windows 宽屏表格、Android 紧凑卡片、员工详情和部门层级。
- Django Admin 管理入口和幂等虚构演示数据命令。

本期不包含员工写入页面、考勤、审批、薪资、招聘、上传、多租户或第三方身份源。

## 目录结构

```text
apps/employee_app/   Flutter Android/Windows 客户端
backend/             Django 模块化单体 API
config/              Flutter 编译期环境配置
deploy/              Docker Compose 与后端镜像
docs/                架构、开发、安全、API、ADR 与计划
scripts/             Windows PowerShell 开发脚本
.github/              CI 与 Pull Request 模板
```

## 前置工具

- Git
- Flutter stable（含 Dart；准确版本以本机成功验证结果为准）
- Android SDK 与可用模拟器，或开启 USB 调试的 Android 设备
- Visual Studio 2022，安装“使用 C++ 的桌面开发”工作负载
- Python 3.12
- Docker Desktop 与 Docker Compose v2

运行 `flutter doctor -v` 并处理 Android、Windows 工具链问题。当前环境检测结果见 [docs/environment-report.md](docs/environment-report.md)。

PowerShell 脚本按 `backend/.venv/Scripts/python.exe`、`py -3.12`、`python` 的顺序选择解释器，不要求开发者修改全局 Python PATH。

## 第一次启动

在 PowerShell 中执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1
```

脚本会检查工具、在缺少时从 `.env.example` 创建仅用于开发的 `.env`、创建 `backend/.venv`、安装依赖、启动 PostgreSQL/Redis、执行迁移、解析 Flutter 依赖并运行基础检查。它不会覆盖现有 `.env`，也不会删除 Docker 卷。

Android、Windows 平台工程和 `pubspec.lock` 已由本机 Flutter SDK 生成并纳入版本控制。日常开发不需要重复运行 `flutter create`；只有明确要重新生成平台文件时，才在审查现有改动后执行：

```powershell
cd apps\employee_app
flutter create --platforms=android,windows --org com.yourcompany --project-name employee_app .
flutter pub get
```

该命令只允许生成 Android 与 Windows；执行前后必须审查差异，不得增加其他平台或覆盖业务实现。

## 启动后端

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-backend.ps1
```

开发服务器监听 `0.0.0.0:8000`。这便于 Android 真机访问，但会扩大局域网暴露面；请只在可信网络使用，并检查 Windows 防火墙入站规则。

可用端点：

- `GET http://127.0.0.1:8000/api/v1/health/`
- `POST http://127.0.0.1:8000/api/v1/auth/login/`
- `POST http://127.0.0.1:8000/api/v1/auth/refresh/`
- `GET http://127.0.0.1:8000/api/v1/me/`
- `GET http://127.0.0.1:8000/api/v1/departments/`
- `GET http://127.0.0.1:8000/api/v1/positions/`
- `GET http://127.0.0.1:8000/api/v1/employees/`
- `GET http://127.0.0.1:8000/api/schema/`
- `GET http://127.0.0.1:8000/api/docs/`

## 初始化虚构演示数据

先把自选开发密码放入当前 PowerShell 进程，不要写入命令、文档或 Git：

```powershell
$securePassword = Read-Host "演示账号密码" -AsSecureString
$env:EMPLOYEE_DEMO_PASSWORD = [System.Net.NetworkCredential]::new("", $securePassword).Password
try {
  .\backend\.venv\Scripts\python.exe .\backend\manage.py seed_demo_data
} finally {
  Remove-Item Env:EMPLOYEE_DEMO_PASSWORD -ErrorAction SilentlyContinue
}
```

命令可重复执行，不会重复创建数据。开发登录名固定为 `demo.employee`；正式登录标识仍是发布前未决事项。完整说明见 [docs/employee-directory-mvp.md](docs/employee-directory-mvp.md)。

## 启动 Windows 客户端

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-flutter-windows.ps1
```

该脚本使用 `config/dev.windows.json`，API 地址为 `http://127.0.0.1:8000/api/v1`。

## 启动 Android 模拟器

先启动模拟器，然后执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-flutter-android.ps1
```

默认使用 `config/dev.android-emulator.json`，其中 `10.0.2.2` 指向开发电脑宿主机。

指定设备：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-flutter-android.ps1 -DeviceId "emulator-5554"
```

## Android 真机连接

1. 复制 `config/dev.android-device.example.json` 为不含敏感信息的本地配置。
2. 将 `YOUR_COMPUTER_LAN_IP` 替换为开发电脑局域网 IP。
3. 保证手机与电脑位于同一可信网络。
4. 允许 Windows 防火墙访问开发端口 8000。
5. 使用 `-ConfigFile` 指定配置：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-flutter-android.ps1 `
  -DeviceId "YOUR_DEVICE_ID" `
  -ConfigFile "config\dev.android-device.json"
```

不要把公网地址、Token 或密码写入 Dart define JSON。

## 测试与质量检查

全量检查：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check.ps1
```

后端单独检查：

```powershell
cd backend
.\.venv\Scripts\python.exe -m ruff format --check --no-cache .
.\.venv\Scripts\python.exe -m ruff check --no-cache .
.\.venv\Scripts\python.exe manage.py check
.\.venv\Scripts\python.exe -m pytest
```

Flutter 单独检查：

```powershell
cd apps\employee_app
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build windows --debug --dart-define-from-file=../../config/dev.windows.json
flutter build apk --debug --dart-define-from-file=../../config/dev.android-emulator.json
```

## 常见问题

- **Flutter 命令不存在**：安装 Flutter stable 并让当前终端能发现 `flutter/bin`，重新打开终端后用 `flutter --version` 记录准确版本。
- **Windows 构建失败**：在 Visual Studio Installer 中安装“使用 C++ 的桌面开发”，再运行 `flutter doctor -v`。
- **Android 模拟器无法访问后端**：确认使用 `10.0.2.2`，而不是 `127.0.0.1`。
- **真机无法访问**：确认局域网、防火墙与 `0.0.0.0:8000` 监听状态；不要在公共网络暴露开发服务器。
- **数据库连接超时**：运行 `docker compose -f deploy/docker-compose.dev.yml ps`，确认 db 为 healthy。
- **Ruff 在受限沙箱无法写缓存**：使用仓库命令中的 `--no-cache`，检查逻辑不受影响。

## 禁止提交的敏感文件

不要提交 `.env`、证书、私钥、Android keystore、`key.properties`、Token、数据库导出、真实员工数据或本地设备配置。`.gitignore` 已覆盖常见文件，但提交前仍需人工检查。

## 下一步

第二阶段已经具备 HR 员工/部门/岗位维护、Django model-permission RBAC、append-only 操作审计、员工离职/复职和 Refresh Token 服务端吊销。设计与验收证据见 [ADR-0004](docs/decisions/ADR-0004-hr-directory-management-security.md) 和 [第二阶段验收报告](docs/hr-directory-management-validation-report.md)。

下一阶段先处理正式 applicationId/Windows 标识、账号邀请/密码重置、账号恢复流程与审计保留/导出策略。不要直接跳到考勤、审批或薪资。
