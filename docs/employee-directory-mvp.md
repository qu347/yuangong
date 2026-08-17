# 身份认证与员工目录 MVP

## 范围

本期提供 JWT 登录/刷新/当前用户、部门与岗位只读目录、员工分页/搜索/筛选/详情、客户端退出登录以及 Django Admin 数据管理。Windows 与 Android 共用 Repository、状态和路由，分别采用适合宽屏与移动端的目录布局。

不包含员工写 API、Flutter 管理表单、考勤、审批、薪资、招聘、上传、多租户、外部 SSO 或复杂 RBAC。

## 启动 Docker 服务

```powershell
docker compose -f .\deploy\docker-compose.dev.yml up -d --build
docker compose -f .\deploy\docker-compose.dev.yml ps
```

期望 `db`、`redis` 为 healthy，`api` 为 running。不要执行 `down -v` 或删除命名卷。

## 初始化虚构数据

命令只接受当前进程环境变量中的密码，不提供仓库默认值：

```powershell
$securePassword = Read-Host "演示账号密码" -AsSecureString
$env:EMPLOYEE_DEMO_PASSWORD = [System.Net.NetworkCredential]::new("", $securePassword).Password
try {
  .\backend\.venv\Scripts\python.exe .\backend\manage.py seed_demo_data
} finally {
  Remove-Item Env:EMPLOYEE_DEMO_PASSWORD -ErrorAction SilentlyContinue
}
```

- 登录名：`demo.employee`
- 数据：4 个部门、6 个岗位、12 名虚构员工
- 邮箱：仅 `example.test`
- 电话：仅虚构工作号码
- 重复执行：对象数量不增长，演示账号密码更新为本次进程值

不要在截图、日志、报告、shell history 或 Git 中记录执行时密码。

## API

| 方法 | 路径 | 认证 | 用途 |
| --- | --- | --- | --- |
| POST | `/api/v1/auth/login/` | 否 | 获取 Access/Refresh Token |
| POST | `/api/v1/auth/refresh/` | 否 | 刷新 Access Token |
| GET | `/api/v1/me/` | 是 | 当前用户和关联员工摘要 |
| GET | `/api/v1/departments/` | 是 | 部门目录 |
| GET | `/api/v1/departments/{id}/` | 是 | 部门详情 |
| GET | `/api/v1/positions/` | 是 | 岗位目录 |
| GET | `/api/v1/employees/` | 是 | 员工列表、搜索、筛选、分页 |
| GET | `/api/v1/employees/{id}/` | 是 | 员工目录详情 |

OpenAPI：`http://127.0.0.1:8000/api/schema/`

Swagger UI：`http://127.0.0.1:8000/api/docs/`

## Token 生命周期

- Access Token：15 分钟。
- Refresh Token：7 天。
- Flutter 安全存储分别保存两种 Token。
- 并发 401 共用一个刷新请求；刷新成功后重试原请求。
- 刷新失败或退出登录时清理 Token 并回到 `/login`。
- 本期未启用服务端黑名单，正式发布前需要评估即时吊销需求。

## 角色与权限

| 能力 | employee | hr_admin | system_admin |
| --- | --- | --- | --- |
| 当前用户 | 读取 | 读取 | 读取 |
| 部门/岗位/员工目录 | 读取 | 读取 | 读取 |
| 目录写 API | 不提供 | 不提供 | 不提供 |
| Django Admin | 否 | 需 `is_staff` | 需 `is_staff`/超级用户 |

## 测试

```powershell
cd backend
.\.venv\Scripts\python.exe -m ruff format --check --no-cache .
.\.venv\Scripts\python.exe -m ruff check --no-cache .
.\.venv\Scripts\python.exe manage.py check --settings=config.settings.test
.\.venv\Scripts\python.exe manage.py makemigrations --check --dry-run
.\.venv\Scripts\python.exe -m pytest

cd ..\apps\employee_app
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test

cd ..\..
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1
```

PostgreSQL 模式按 `docs/development.md` 设置 `TEST_DATABASE_ENGINE=postgresql` 与 Compose `POSTGRES_*` 后运行同一 pytest。

## 启动客户端

Windows：

```powershell
.\scripts\run-flutter-windows.ps1
```

Android 模拟器：

```powershell
.\scripts\run-flutter-android.ps1 -DeviceId emulator-5554
```

Windows 使用 `config/dev.windows.json`；Android 模拟器使用 `config/dev.android-emulator.json`。Android 的 `10.0.2.2` 仅用于模拟器访问宿主机开发 API。

## 已知限制

- Android `applicationId`/namespace 与 Windows 发布标识仍是开发占位符。
- username 不是已批准的正式企业登录标识。
- Windows 构建在本机仍需要进程级 `TrackFileAccess=false`。
- Flutter 3.47/aapt 36 对中文工作区 APK manifest 检查会回退到源 manifest，但构建、安装与运行已真实验证。
- 既有 Pub Cache 生成元数据警告继续保留，本阶段未重复 `flutter pub get`。
