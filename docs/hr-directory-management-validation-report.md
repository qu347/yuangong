# HR 目录管理第二阶段验收报告

- 验收日期：2026-08-17
- 分支：`feature/hr-directory-management`
- 基线：`0ab87c7`
- 设计：`docs/decisions/ADR-0004-hr-directory-management-security.md`
- 计划：`docs/plans/0005-hr-directory-management.md`

## 1. 结论

第二阶段验收通过。系统已经从只读员工目录升级为具备后端强制 RBAC、目录写服务、append-only 审计、员工生命周期、Refresh Token rotation/blacklist 与 Windows/Android capability 驱动管理界面的可运行工程。

没有实现物理删除、薪资、考勤、审批、招聘、多租户、外部 SSO、账号邀请/密码重置或生产发布。没有创建 iOS、Web、macOS、Linux 平台文件，没有运行 `flutter create`，没有生成新的项目 `pubspec.lock`，没有 push。

## 2. 后端能力

- RBAC：Django Group/model permissions；`employee` 3 项只读权限，`hr_admin` 与 `system_admin` 各 10 项目录管理/审计权限。
- `sync_rbac`：连续运行结果一致，只补充权限，不清除额外授权。
- `/me/`：返回五个稳定 capabilities。
- JWT：Access 15 分钟、Refresh 7 天、rotation 与官方 blacklist 开启；inactive User 不能认证或刷新。
- 会话：logout 204、logout 幂等、logout-all 按当前用户隔离并返回吊销数量。
- 目录：Department、Position、Employee 支持 POST/PATCH 与显式状态 action；所有 DELETE 均未提供。
- Employee：支持 `expected_updated_at` stale 检查；depart 幂等停用关联账号并吊销已登记 Refresh；reactivate 不自动恢复账号。
- AuditEvent：append-only、actor SET_NULL、API/Admin 只读、默认倒序、分页/过滤、敏感 changes 白名单。
- Admin：目录 create/update 有审计，删除禁用；Employee status/user 只读。
- 错误合同：`code/message/details/request_id`；400/401/403/404/405/409 稳定小写错误码。

## 3. Flutter 能力

- 复用单一 Riverpod/go_router/Dio/TokenStorage；没有第二套认证、网络或路由。
- capabilities 控制管理入口和深链 guard；后端仍执行最终授权。
- ApiClient 支持 PATCH、204 action、409 安全错误码和现有 single-flight refresh。
- logout 先尝试服务端吊销并在 finally 清本地；logout-all 吊销所有设备会话后退出。
- 员工新增/编辑、active 部门/岗位筛选、stale 提示、保存防重复、失败保留输入、未保存 PopScope 保护。
- depart/reactivate 确认与账号不自动恢复提示。
- 部门/岗位管理与状态 action；审计只读列表和安全 changes 摘要。
- Windows/Android 使用现有 900 响应式断点和统一导航壳。

## 4. 自动化证据

| 检查 | 结果 |
| --- | --- |
| `scripts/check.ps1` | PASSED，最终退出码 0 |
| Dart format | 74 个文件，0 变更 |
| Flutter analyze | No issues found |
| Flutter unit/widget | 66/66 PASSED |
| Ruff format/check | PASSED |
| Django check | 0 issue |
| SQLite pytest | 75/75 PASSED |
| PostgreSQL pytest | 75/75 PASSED |
| `makemigrations --check --dry-run` | No changes detected |
| OpenAPI `--validate --fail-on-warn` | PASSED，0 warning/error |
| Windows 真实 API integration | 1/1 PASSED |
| Android 真实 API integration | 1/1 PASSED |

PostgreSQL 测试发现并修复了两个 SQLite 不会暴露的真实问题：nullable `select_related()` 被纳入 `FOR UPDATE`，以及 OutstandingToken 默认 user 排序/blacklist 外连接被一并锁定。最终实现均使用 `select_for_update(of=("self",))`，Token 查询同时显式 `order_by("pk")`；完整 PostgreSQL 套件复验通过。

## 5. PostgreSQL、Redis 与迁移

升级前只读统计：3 Group/1 User/4 Department/6 Position/12 Employee，6 个 Position 均有 Department；Group permissions 全为 0。

原地应用：

- `audit.0001_initial`
- `organizations.0002_position_department_required`
- SimpleJWT `token_blacklist` 官方 13 个 migration

升级后 RBAC 为 employee=3、hr_admin=10、system_admin=10。PostgreSQL/Redis 容器保持 healthy，Redis `PING` 返回 `PONG`；没有 flush/drop、`down -v`、prune 或 volume 删除。

真实 HTTP 验收状态：employee 写入 403、me capabilities 200、旧 Refresh replay 401、目录写流 200/201、员工生命周期 200、审计读取 200、logout 204、logout replay 401、logout-all 200、logout-all 后 Refresh replay 401。

验收只使用唯一前缀虚构数据。由于本轮禁止物理删除，最终保留 10 个 inactive 验证账号、2 个 inactive 验证部门、1 个 inactive 岗位、1 个 departed 员工；所有 13 个 Outstanding Token 均已 blacklist，active 验证账号/部门/岗位/员工均为 0。AuditEvent 共 14 条。API 最近 30 分钟日志中敏感值模式计数为 0，错误模式计数为 0。

## 6. Windows 验收

- 最终构建：41.6 秒，使用 `config/dev.windows.json`。
- 仅构建进程设置 `TrackFileAccess=false`，没有持久修改系统或 Visual Studio。
- EXE：`D:\员工管理\apps\employee_app\build\windows\x64\runner\Debug\employee_app.exe`
- 大小：983,040 字节。
- SHA-256：`769AFE9978660356D85C9AF1CB8623926002CAA6C92D35BBA770B50C13A41601`
- 隐藏启动 PID 32420，HasExited=false、Responding=true；验收后只结束该进程。
- 真实 UI/API integration：HR 登录→新增员工表单→审计日志→员工搜索/详情→部门→服务端 logout，PASSED。

## 7. Android 验收

- AVD：`employee_api36` / `emulator-5554`，boot_completed=1，API 36。
- Gradle：新 `powershell.exe -NoProfile` 从真实用户持久配置加载 `D:\DevCaches\Gradle`；未使用隔离目录、人工 Maven 缓存、临时代理或 `--offline`。
- 最终构建：29.8 秒，使用 `config/dev.android-emulator.json`。
- APK：`D:\员工管理\apps\employee_app\build\app\outputs\flutter-apk\app-debug.apk`
- 大小：232,355,573 字节。
- SHA-256：`1F13DCF28053ABDC40C633A722B728EE32E7A7CE34592740A48C9314FB3563FE`
- `adb install -r`：Success。
- 最终 PID：6778；`topResumedActivity` 为 `com.yourcompany.employee_app/.MainActivity`；包级 FATAL 行数 0。
- 真实 UI/API integration：与 Windows 相同流程，1/1 PASSED。

非阻塞警告：`am start -W` 返回 timeout，但 3 秒后 PID、前台 Activity 与 FATAL=0 均通过；aapt 36 无法直接读取中文路径 APK，Flutter 回退源 Manifest 后构建、安装和运行均成功。

## 8. 开发环境观察

真实用户 `QU\quwenxin` 的持久用户配置仍为 `GRADLE_USER_HOME=D:\DevCaches\Gradle`、`PUB_CACHE=D:\DevCaches\Pub\Cache`。Codex 沙箱进程继承精简环境时看不到这两个变量，直接 wrapper 会尝试在默认 C 盘下载 Gradle 9.3.1；本轮中止该下载，C 盘仅留下 0 字节 `.lck/.part` 占位，不做删除。正式 Android 验收在新的真实用户 PowerShell 中从持久用户配置加载同值。

## 9. Git 与安全审查

- 本阶段本地提交目标：5 个逻辑提交。
- 已知 `origin` 来自上一轮用户授权上传；本阶段 push=否。
- 未执行 reset、clean、restore、rebase、amend、强制覆盖或删除未跟踪文件。
- 用户侧未跟踪 `docs/environment-configuration.md` 保持不动且未纳入提交。
- 未提交 `.env`、密码、Token、证书、签名、数据库凭据或真实员工数据。

## 10. 已知限制

- applicationId/Windows 标识仍为开发占位符。
- Access Token 在普通 logout/logout-all 后最长仍有效 15 分钟。
- blacklist 启用前未登记的历史 Refresh Token 无法追溯。
- Flutter 暂无账号恢复页面；reactivate 只恢复 Employee。
- 审计暂无导出、保留/归档策略和复杂对象级/字段级 RBAC。
- Windows 构建仍依赖仅进程级 FileTracker 兼容设置；Android 仍有中文路径 aapt 警告。
