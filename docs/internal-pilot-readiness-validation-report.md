# 第四阶段：内部试用交付准备验收报告

验收日期：2026-08-19 至 2026-08-20（Asia/Shanghai）

## 1. 总体结论

- 最终状态：**PASSED WITH WARNINGS**。
- 分支：`feature/internal-pilot-readiness`。
- worktree：`D:\Worktrees\yuangong-phase4`。
- 基线：`origin/main@4d200113ed183f5c84f89bccf05dc4a6b2db5043`，包含 PR #4。
- 发布验证 HEAD：`e1a69d3018d4b51bab86a64e77bf5dbb9f8f55e3`。
- 最终文档提交：`test(docs): record phase four validation`；其准确 SHA 由最终 `git log` 和任务回复记录。
- 是否 push：否。
- 是否创建 PR：否。
- 是否修改 GitHub 设置：否。

代码、迁移、本地数据库、审计导出/归档、production-like 容器、Windows/Android ValidationOnly 和统一门禁均通过。正式身份、正式证书、staging SMTP、GitHub visibility/ruleset、远端第四阶段 CI、安装包格式、分发渠道和法定保留期限仍是外部事项，因此不能标记 PASSED 或正式发布。

## 2. GitHub 基线

- PR #4 merge/main SHA：`4d200113ed183f5c84f89bccf05dc4a6b2db5043`。
- 最新 main CI：run `32211539467`，workflow `CI`，结论 success，HEAD `4d200113...`。
- visibility：public；default branch：main。
- main protected：false；rulesets：0。
- 直接协作者：1。
- Actions：enabled，allowed actions 为 all；默认 workflow permission 为 read，不能批准 PR review。
- secret scanning：enabled；push protection：enabled；Dependabot security updates：disabled。

上述值在最终报告前重新只读获取。因为只有一名协作者且没有授权，未应用 visibility、branch protection、ruleset、Secrets、Environments 或 Actions 权限变更。

## 3. 审计导出

- 权限：`audit.export_auditevent`，system_admin only；客户端 capability 为 `can_export_audit`。
- 端点：`GET /api/v1/audit-events/export.csv`。
- 过滤：actor/action/resource/resource_id/UTC 时间范围/白名单 ordering。
- 上限：10000；超限返回 `export_too_large`，无数据样本。
- CSV：固定列、UTF-8 BOM、CRLF、标准 writer、稳定 changes JSON；公式危险前缀增加单引号。
- 实际导出：1 行虚构验证事件；BOM、中文、公式转义均通过。
- 文件：`D:\EmployeeReleaseValidation\Audit\audit-events-20260820T035246Z.csv`。
- SHA-256：`4bbadfcf7db6e3fbc8ef55408e174003466f14e8f0d35aa8f577a9eac242e630`。
- 成功导出审计：1 条 `audit_exported`。
- 虚构 system_admin 验收账号最终 `is_active=false`，活动会话 0。

## 4. 审计归档

- Batch：`e117dd98-7154-4f92-b765-186b30c7d595`，completed。
- 格式：稳定排序 UTF-8 JSONL gzip + schema 1 manifest。
- 事件数量：50。
- 归档目录：`D:\EmployeeAuditArchives\Validation\phase4-20260820T035526613Z`。
- SHA-256：`7c0ee13c7751029ebe7941b511752c9a44a82ba427bde32fcb1c247cad38552a`。
- HMAC：HMAC-SHA256，key ID `phase4-validation-v1`；key 未输出、未写入报告或 Git。
- manifest Git SHA：`22856f45c32a5980e2aebb2f26ecc7e1638ccafb`。
- 篡改测试：复制归档后翻转一字节，verify 非 0；已只删除明确的 `Tamper-<batch-id>` 副本。
- 数据库审计数量：归档前 50，归档后 50；没有删除。

有效归档和 manifest 保留。验收 key 只存在于执行进程，没有持久化；未来重新执行 HMAC 验证必须由授权方提供相同 key。

## 5. 保留策略

- `AUDIT_RETENTION_DAYS=0`：无限期保留。
- total events：50；candidate：0；unarchived candidate：0。
- completed archives：1。
- 自动删除：false；没有 purge 命令。
- 法定保留期限：未决定。

## 6. 生产安全

- `check --deploy`：通过，0 issue。
- Django secret、JWT signing、账号 Token keyring、归档 keyring：相互独立，production 无不安全默认值。
- 一次性 Token：新 token 记录 key ID；unknown key 拒绝；legacy count 0。
- HTTPS：production 强制；可信代理头只在显式开关后使用。
- 数据库：PostgreSQL；缓存：Redis。
- production Compose healthcheck 初次发现 HTTP 301，已用回归测试修复为可信 `X-Forwarded-Proto: https`。

## 7. 邮件

- development：Mailpit，仅 `.invalid` 虚构地址。
- tests：locmem。
- production：通用 SMTP 必填合同，TLS/SSL 冲突和 Mailpit/localhost 被拒绝。
- staging 实际发送：**NOT RUN**，未提供 SMTP 凭据和授权收件人。

## 8. 发布身份

- 产品名：企业员工管理系统（仍是开发/验证名称）。
- version/build：`0.1.0+1`。
- Android applicationId/namespace：`com.yourcompany.employee_app`，占位。
- Windows publisher：开发占位；Publisher CN 未提供。
- API：`https://validation.invalid/api/v1`，仅验证占位。
- 严格身份检查：按预期拒绝；显式 AllowDevelopmentPlaceholders 返回 validation_only=true。

## 9. Android

- Release Validation APK：`D:\EmployeeReleaseValidation\Builds\phase4-verified-20260820T042343565Z\ANDROID-NON-DISTRIBUTABLE.apk`。
- 大小：55,511,165 bytes。
- SHA-256：`7f204258adebd15625068120c41987f5b59e8dbb73506b71a8ec9d32f4d81848`。
- 签名：有效的一次性 ValidationOnly RSA 证书；证书 SHA-256 `f6e6c8d695742f6cf6a79ba7a5af4f5e0f5c9d255816f7fba8360ebce6c7893c`。
- applicationId/versionName/versionCode：`com.yourcompany.employee_app` / `0.1.0` / `1`。
- 设备：`employee_api36` / `emulator-5554`。
- 安装：Success。因旧 Debug 签名不兼容，经用户明确授权先卸载旧应用；旧模拟器应用本地数据已删除。
- PID：4850；前台：`com.yourcompany.employee_app/.MainActivity`；AndroidRuntime FATAL：0。
- 状态：**SIGNED WITH TEMPORARY VALIDATION CERTIFICATE / NON-DISTRIBUTABLE**。

构建有 Android SDK XML 版本提示和未使用 CupertinoIcons 字体提示，但 APK、签名、安装、进程、Activity 和 FATAL 验证均通过。

## 10. Windows

- Release ZIP：`D:\EmployeeReleaseValidation\Builds\phase4-verified-20260820T042343565Z\WINDOWS-UNSIGNED-NON-DISTRIBUTABLE.zip`。
- 大小：12,518,476 bytes。
- SHA-256：`dd7537edc146ffe2d3b385d1aab221ebafbeb43854147dac7885ae350c06c4db`。
- 签名：NotSigned；无正式 PFX。
- 实际启动 PID：29724；窗口句柄存在；Responding=true。
- `CloseMainWindow()`：true；正常退出：true；exit code 0。
- 状态：**UNSIGNED / NON-DISTRIBUTABLE**。

## 11. Docker

- development Compose：api running；PostgreSQL 17 healthy；Redis 8 healthy/PONG；Mailpit healthy。
- production example：`config --quiet` 通过，服务仅 db/redis/api，无 Mailpit。
- production image：`sha256:83c6bd57107f668b09d02bd37eacf86a02f411e5486efada975728bed037e6ee`。
- runtime user：`app` / UID 10001。
- health：status ok，database ok；Redis PONG。
- 镜像检查：无 `.env`、`.git`、venv、pyc、SQLite、tests。
- 声明边界：production-like local smoke only；没有公网、真实 TLS、真实 SMTP 或生产数据部署。

## 12. GitHub 治理

- 新增 SECURITY policy、Dependabot pip/pub/github-actions、PR checklist、治理文档和发布检查清单。
- CodeQL：官方 v4.37.7 完整 SHA，仅 Python；不声称 Dart 支持。
- release-readiness：仅 workflow_dispatch、contents read、无 Secrets 引用、不上传/发布产物。
- required checks 建议：`backend-sqlite`、`backend-postgresql`、`flutter-quality`、`android-build`、`windows-build`、`repository-safety`。
- branch protection/ruleset/visibility：未应用。
- CODEOWNERS：未创建，因为只有一名可核实协作者。

## 13. 自动化

- Dart format：103 files，0 changed。
- Flutter analyze：0 issue；Flutter tests：91/91。
- Ruff format：126 files；Ruff lint：通过。
- Django check：0 issue；migration drift：0。
- 第四阶段聚焦合同：30/30。
- SQLite：178/178。
- PostgreSQL：174 passed、4 Windows PowerShell-only skipped；同 4 项在 Windows 主机通过，Linux 仍执行 2 个可移植发布合同。
- Redis：PONG。
- OpenAPI strict：exit 0，0 warning/error。
- dev/production Compose config：通过。
- release PowerShell contracts：通过。
- repository safety：通过。
- `scripts/check.ps1`：exit 0。
- actionlint：**NOT RUN**，本机未安装；没有把 YAML 解析测试冒充 actionlint。

## 14. Git

本阶段本地提交：

1. `48c2eb4 docs: define audit governance and release readiness`
2. `8ca8c1c feat(audit): add secure audit export`
3. `b880c7a feat(audit): add verifiable non-destructive archives`
4. `d22ce5c feat(security): add production key and email contracts`
5. `3e54f0f feat(app): add governed audit export flow`
6. `ede248d build: add internal release validation tooling`
7. `22856f4 ci: harden repository and release-readiness checks`
8. `90cc4d1 fix(release): harden validation runtime`
9. `e1a69d3 fix(release): resolve persisted Android SDK`
10. `test(docs): record phase four validation`（准确 SHA 见最终任务回复）。

额外两个 fix 是真实验收中发现的 Windows PowerShell stderr、production health 301 和用户级 Android SDK 继承问题；没有 amend/rebase 重写历史。四个临时 detached 构建 worktree已删除，外部证据保留。主工作区 `docs/environment-configuration.md` 保持未跟踪、未修改、未暂存。

## 15. 遗留项

### 阻塞正式发布

- 正式 applicationId/namespace、产品与公司法定身份、Windows Publisher CN。
- Android 正式 keystore、Windows 正式 PFX/时间戳服务。
- staging SMTP、正式 API/TLS/DNS、分发渠道和 Windows 安装包格式。

### 高

- public 仓库是否符合公司政策；既有公开 fork/历史不可通过改 private 收回。
- main 无保护且只有一名协作者；必须先增加可审查人员再应用一名审批规则。

### 中

- 法定审计保留期限、正式归档介质、key 托管和未来双人清理流程未决定。
- CodeQL/Dependabot/release-readiness 尚未在第四阶段远端分支运行。

### 低/非阻塞警告

- actionlint 未安装。
- Android SDK XML/CupertinoIcons 构建提示应在后续工具链维护中处理。
- Windows 控制台读取中文标题出现编码显示问题，但窗口、响应和正常退出验证通过。

## 16. 下一阶段

下一阶段只考虑正式内测试点部署、SMTP 接入、正式签名证书、受控安装包分发、备份恢复演练、灾难恢复、监控告警和生产运维手册。不得直接扩展考勤、薪资或复杂审批。
