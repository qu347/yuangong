# 企业员工管理系统

面向企业内部员工的 Windows 与 Android 管理客户端。当前已完成员工目录、HR 维护、RBAC/审计、账号与会话安全，以及受控审计导出、可验证归档、生产配置合同和内部试用构建验证；仍不包含考勤、审批、薪资等完整人力资源业务。

## 平台范围

当前支持：

- Windows 桌面端
- Android 手机端（模拟器与真机）

当前不支持：iOS、macOS、Web、Linux。iOS 仅作为未来可能扩展，不在当前工程中创建或构建。

## 技术栈

- 客户端：Flutter stable、Dart、Material 3、Riverpod、go_router、Dio、flutter_secure_storage
- 后端：Python 3.12、Django 5.2.x、Django REST Framework、SimpleJWT、drf-spectacular、pytest、Ruff
- 基础设施：PostgreSQL 17、Redis 8、Mailpit、Docker Compose
- 协作：GitHub Actions、Pull Request 模板、ADR

## 已实现能力

- 用户名或账号邮箱登录、JWT rotation、`sid` 会话绑定和 Access/Refresh 即时吊销。
- system_admin 账号邀请、重发/撤销、初始密码、停用/恢复和 employee/hr_admin 角色调整。
- 忘记密码通用响应、一次性重置码、登录用户修改密码和多设备会话管理。
- 部门、岗位和员工目录读写，以及员工离职/恢复。
- 员工姓名/工号/工作邮箱搜索，部门和在职状态筛选，受限分页与排序。
- Windows 宽屏表格、Android 紧凑卡片、员工详情和部门层级。
- Django model-permission RBAC、append-only 审计、Django Admin 和幂等虚构演示数据命令。
- system_admin 专属审计 CSV 导出、公式注入防护、导出上限和导出行为自身审计。
- gzip JSONL 审计归档、SHA-256/HMAC manifest、篡改验证和只读保留报告；不自动删除审计。
- production settings/SMTP/keyring/非 root Gunicorn 镜像合同，以及 Windows/Android `NON-DISTRIBUTABLE` 发布验证。
- PostgreSQL/Redis/Mailpit 本地 Compose、六 job 基础 CI、Dependabot、Python CodeQL 和手动 release-readiness 工作流。

当前不包含考勤、审批、薪资、招聘、上传、多租户、MFA、外部 SSO 或生产邮件供应商。

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
- `POST http://127.0.0.1:8000/api/v1/auth/password-reset/request/`
- `GET http://127.0.0.1:8000/api/v1/auth/sessions/`
- `GET http://127.0.0.1:8000/api/v1/accounts/`
- `GET http://127.0.0.1:8000/api/v1/accounts/invitations/`
- `GET http://127.0.0.1:8000/api/v1/departments/`
- `GET http://127.0.0.1:8000/api/v1/positions/`
- `GET http://127.0.0.1:8000/api/v1/employees/`
- `GET http://127.0.0.1:8000/api/v1/audit-events/export.csv`
- `GET http://127.0.0.1:8000/api/schema/`
- `GET http://127.0.0.1:8000/api/docs/`

开发 Compose 的 Mailpit UI 只绑定 `http://127.0.0.1:8025`。它仅用于捕获 `.invalid` 本地测试邮件；普通 API 不返回邀请码或重置码，production settings 也不会默认使用 Mailpit。

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

生产变量、审计治理和内部试用构建分别见 [生产配置](docs/production-configuration.md)、[审计治理](docs/audit-governance.md) 和 [发布检查清单](docs/release-checklist.md)。第四阶段真实结果见 [内部试用准备验收报告](docs/internal-pilot-readiness-validation-report.md)。

## 下一步

第四阶段已经具备内部试用交付的代码和本地验证基础，但正式身份、SMTP、Android/Windows 正式证书、审计法定保留期限、仓库 visibility 与 main 保护仍需公司决策和授权。

下一阶段只考虑正式内测试点部署、SMTP 接入、正式签名、受控分发、备份恢复与监控告警。不要直接跳到考勤、审批或薪资。
