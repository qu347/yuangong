# 第三阶段账号生命周期与会话安全验收报告

验收日期：2026-08-18（Asia/Shanghai）

## 1. 总体结论

```text
最终状态：PASSED WITH WARNINGS
分支：feature/account-lifecycle-security
基线：origin/main d64b12231232a79b55b4430d6e1823b617478785
报告编写时 HEAD：0ae8070
新增提交：5 个功能提交；最终文档提交在报告写入后生成
工作区：除用户既有 docs/environment-configuration.md 外，最终要求无其他变化
远程：origin = https://github.com/qu347/yuangong.git
是否 push：否
是否创建 PR：否
远端 CI：NOT RUN
```

本地第三阶段实现、双数据库、Redis、Mailpit、Windows、Android 与构建产物验收通过。唯一决定最终状态不能标为 PASSED 的新增警告是：CI workflow 已完成本地审查和命令复验，但本阶段未获 push 授权，因此 GitHub Actions 尚未远端运行。

## 2. Git 基线验证

- PR #1 已合并到 `main`，远端合并提交为 `273c23c`。
- PR #2 原先只合并到功能分支；经用户明确授权，纠正 PR #3 将两阶段结果传播到 `main`，远端基线为 `d64b122`。
- 新分支从该 `origin/main` 真实树创建；没有从旧功能分支继续堆叠。
- 已核对合并树而非假设旧功能提交 `57d4bc1` 必须是直接祖先，兼容 GitHub merge/squash/rebase merge 差异。
- 全程未执行 reset、clean、restore、rebase、amend、force push 或分支删除。

## 3. 账号生命周期

- system_admin 可创建、查看、重发和撤销邀请；anonymous 为 401，employee/hr_admin 为 403。
- 邀请只允许 active、未绑定 User 的 Employee；用户名、非空账号邮箱和同一员工有效邀请受冲突约束。
- 接受邀请使用事务、行锁与一次性摘要，创建 User、绑定 Employee、分配 employee/hr_admin，不自动登录。
- 业务 API 不提供 system_admin 角色选项，不管理超级用户/system_admin，也不允许管理员停用自己。
- 停用账号立即撤销会话，但不改变 Employee 状态；恢复要求关联 Employee 仍 active，且不恢复旧会话。
- 角色只允许 employee/hr_admin，调整会撤销全部会话。
- `User.email` 是登录/邀请/恢复邮箱，`Employee.work_email` 是目录邮箱；两者不自动同步，UI 显示不一致提示。
- Windows 与 Android 共享 Flutter integration 均真实执行邀请接受、账号登录、停用和恢复。

## 4. 密码安全

- 最少 12 字符，复用 Django common、numeric、user attribute similarity validators，并补充员工姓名/工号上下文。
- 忘记密码对不存在、inactive、无邮箱和有效账号统一返回 202 通用消息。
- 重置码默认 30 分钟；新请求撤销旧码，过期/已用/已撤销统一拒绝。
- 邀请码默认 48 小时；重发替换摘要，旧码、撤销码、过期码和已用码均失败。
- 密码修改与重置使用 `set_password()`，成功后撤销全部会话并要求重新登录。
- Mailpit 真实重置结果：确认 204、重复使用 400、旧密码 401、新密码 200。
- 密码、一次性码、Token、JTI 与邮件正文均未进入 API、审计或验收报告。

## 5. 会话安全

- `AccountSession` 记录用户、平台、客户端名、版本、创建/活动/到期时间、当前 Refresh JTI 和撤销状态；API 不返回 JTI。
- 登录创建会话，Access/Refresh 含相同 `sid`；Refresh rotation 保留 sid、更新 JTI，旧 Refresh replay 失败。
- `SessionJWTAuthentication` 每次检查 active User 与 active Session；`last_seen_at` 以 5 分钟节流写入。
- 单会话、其他会话、logout、logout-all、管理员撤销、密码变化、账号停用、角色变化均有服务端撤销路径。
- 真实 Mailpit 重置后旧 Access=401、旧 Refresh=401；被撤销 Access 无需等待 15 分钟过期。
- 缺少 sid 的旧 Access/Refresh 统一拒绝，第三阶段部署后要求重新登录。
- 最终数据库共有 27 条验收/既有会话，active sessions=0。

## 6. 邮件验收

- `axllent/mailpit:v1.30.7` healthy，UI 仅绑定 `127.0.0.1:8025`，无持久 volume。
- 最终 Mailpit 共 8 封 `.invalid` 邮件：5 封真实邀请、1 封真实密码重置、2 封 SMTP 基础验证。
- 每次真实邀请或重置的计数增量均为 1；一次性码只由受控验收进程从 Mailpit 读取到内存。
- 邀请 API 响应扫描未出现 token/digest/password；普通 API 没有“查看验证码”端点。
- 应用日志和报告没有邮件正文、邀请码或重置码；Admin 不展示摘要/JTI。
- CI 使用 locmem email backend；production 必须显式配置邮件后端，不默认使用 Mailpit。

## 7. 权限矩阵

| 端点/动作 | anonymous | employee | hr_admin | system_admin |
| --- | ---: | ---: | ---: | ---: |
| GET/POST `/accounts/invitations/` | 401 | 403 | 403 | 200/201 |
| GET `/accounts/`、详情 | 401 | 403 | 403 | 200 |
| 账号邮箱/停用/恢复/角色/撤销会话 | 401 | 403 | 403 | 200（状态冲突为 409） |
| 邀请接受、忘记密码、重置确认 | 公开 | 公开 | 公开 | 公开 |
| 当前用户会话列表/撤销 | 401 | 200 | 200 | 200 |

Flutter 的 capability 和深链守卫只控制入口；所有授权仍由 Django permission classes 与 model permissions 决定。

## 8. 审计

- 新增邀请创建/重发/撤销/接受、密码修改/重置完成、账号停用/恢复、角色变化、单/其他/全部会话撤销 action。
- 最终 `AuditEvent` 总数 42；第三阶段真实闭环产生 invitation_created=5、invitation_accepted=5、password_changed=5、password_reset_completed=1、account_deactivate=3、account_activated=2。
- actor/resource/resource_label 只保存必要账号/资源标识；`changes` 采用允许字段集合并递归拒绝 password/token/jti/authorization/secret/database/redis。
- 失败事务不生成成功审计；自动化测试验证 append-only model/queryset 禁止 update/delete。

## 9. 自动化测试

| 检查 | 结果 |
| --- | --- |
| Flutter format | PASSED |
| Flutter analyze | PASSED，0 issues；中文路径使用已验证 ASCII junction |
| Flutter test | PASSED，83/83 |
| SQLite pytest | PASSED，131/131 |
| PostgreSQL 17 + Redis 8 pytest | PASSED，131/131 |
| Django check | PASSED，0 silenced |
| Ruff format/check | PASSED |
| OpenAPI strict | PASSED，0 warning / 0 error |
| migration check | PASSED，`No changes detected` |
| Windows shared real integration | PASSED，1/1 |
| Android shared real integration | PASSED，1/1 |
| `scripts/check.ps1` | PASSED，Exit Code 0 |

没有删除、弱化或批量 skip 既有测试；真实 integration 只在明确传入进程级开关和凭据时运行。

## 10. CI

- 文件：`.github/workflows/ci.yml`。
- jobs：`backend-sqlite`、`backend-postgresql`、`flutter-quality`、`android-build`、`windows-build`、`repository-safety`。
- 触发：push main、PR main、workflow_dispatch；最小权限 `contents: read`；同分支并发取消。
- 固定 Python 3.12、Flutter 3.47.0、JDK 21、PostgreSQL 17、Redis 8。
- 第三方 Actions 使用完整 SHA；pip/Pub/Gradle 仅缓存依赖，不缓存 `.env`、Token、邮件、测试数据库或签名。
- PR 只验证 APK/EXE 存在和 SHA-256，不上传大体积 Debug 产物。
- YAML 结构、CI 契约、Compose 和各 job 实际命令已本地复验；`actionlint` 未安装，记录 `NOT RUN`，未全局安装。
- 远端 Actions：NOT RUN（未 push，不能描述为远端通过）。

## 11. Windows

```text
EXE：D:\员工管理\apps\employee_app\build\windows\x64\runner\Debug\employee_app.exe
大小：983,040 bytes
SHA-256：8109934904EEAB5599D2DA7DC730AD950D7DE8D289FF0772C7695ECAF690D7B4
进程：PID 14080
窗口：handle 265684，Responding=true，无立即退出
关闭：CloseMainWindow=true，正常退出
业务闭环：共享真实 integration 1/1 PASSED
```

非阻塞警告：本机 MSBuild FileTracker 会静止，最终构建只在该进程设置 `TrackFileAccess=false`，没有持久修改系统或 Visual Studio。

## 12. Android

```text
APK：D:\员工管理\apps\employee_app\build\app\outputs\flutter-apk\app-debug.apk
大小：232,414,067 bytes
SHA-256：BFC0141C1918BED7D73D313F098D52AE3EB247E9EDF9BC4C0A5CD1995797B865
设备：employee_api36 / emulator-5554，boot_completed=1
adb install：Success
应用 PID：4389
前台：com.yourcompany.employee_app/.MainActivity
包级 FATAL：0
业务闭环：共享真实 integration 1/1 PASSED
```

Gradle/Pub 均使用持久 D 盘用户目录，无临时代理、离线参数、隔离 Gradle 或人工 Maven 缓存。中文路径 aapt 回退与 SDK XML version 4 提示不影响构建/安装/运行；一次 `am start -W` timeout 由 PID、前台 Activity 与 FATAL=0 证明为非阻塞。

## 13. 数据库和迁移

- 新迁移：`accounts/0002_account_lifecycle_security.py`、`audit/0002_alter_auditevent_action.py`；均已应用。
- 升级前：User 11（active 1/inactive 10）、Employee 13（active 10/departed 3）、linked Employee 1、Outstanding 13、Blacklisted 13、Audit 14、重复非空邮箱组 0。
- 升级后：User 21（active 1/inactive 20）、Employee 18（active 10/departed 8）、linked Employee 6、Outstanding 40、Blacklisted 40、Audit 42、重复非空邮箱组 0。
- 差异来自 10 个 process-only 验收账号和 5 个虚构验收员工；最终这些账号全部 inactive、会话全部 revoked、员工全部 departed，记录保留用于审计。
- 原 11 个 User、13 个 Employee、部门/岗位和 14 条旧审计均保留；未合并/修改真实冲突邮箱。
- `migrate --noinput` 返回无待应用迁移；`sync_rbac` 连续两次成功；未 fake、flush、drop、squash 或删除 Docker volume。

## 14. Git

本地功能提交：

```text
b6966b5 docs: define account lifecycle and session security
23d0e5f feat(security): add account lifecycle and session registry
962ec07 feat(app): add account security and recovery flows
cb68297 feat(platform): add mailpit and verified ci gates
0ae8070 feat(security): complete account admin safeguards
```

- 最终文档与最后的 integration 稳定性修改将形成第 6 个逻辑本地提交。
- 已知未跟踪文件：`docs/environment-configuration.md`，未修改、未暂存、未提交、未加入 `.gitignore`。
- 远程数量：1（origin）；没有 push、PR、branch protection、Secrets 或 Actions 权限修改。

## 15. 遗留问题

**阻塞：** 无。

**高：** 无。

**中：** 生产邮件供应商、正式身份源、审计保留/归档尚未决策；不能将 Mailpit 用于生产。

**低：** 基础仓库安全脚本只防常见误提交，不是完整秘密扫描器或依赖漏洞扫描器。

**非阻塞警告：** GitHub Actions 尚未 push/远端运行；开发 applicationId/Windows publisher 仍为占位；Windows 需进程级 TrackFileAccess 兼容；中文路径 aapt/SDK XML 与 `am start -W` timeout 已由真实产物、PID、Activity、FATAL 交叉证明不影响结果。

## 16. 下一阶段

第三阶段通过后，第四阶段只考虑：

- 审计导出、保留期限和归档；
- 正式 Android applicationId 与 Windows publisher；
- 生产邮件供应商与密钥轮换；
- GitHub branch protection 和远端 CI 首次验证；
- 正式签名、分发和发布准备。

不得直接扩展薪资、考勤或复杂审批。
