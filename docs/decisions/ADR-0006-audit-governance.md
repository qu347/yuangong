# ADR-0006：审计导出、可验证归档与非破坏性保留治理

- 状态：Accepted
- 日期：2026-08-19
- 适用阶段：第四阶段内部试用交付准备

## 背景

现有 `AuditEvent` 已是 append-only，具备只读 API、过滤、分页、actor `SET_NULL` 与敏感 changes 白名单，但没有受控导出、离线完整性证据、归档批次或保留候选报告。第四阶段需要增加治理能力，同时明确不删除任何审计数据库记录。

## 决策

### 导出权限与 API

新增 Django 自定义权限 `audit.export_auditevent`，仅授予 `system_admin`。`hr_admin` 保留在线查看权限但不能批量导出。`/me/` 增加缺失时默认为 false 的 `can_export_audit`。

新增 `GET /api/v1/audit-events/export.csv`，路由在 UUID detail 之前。导出与列表共用一个显式过滤器，支持 `actor`、`action`、`resource_type`、`resource_id`、`source`、`created_after`、`created_before` 和受限 `ordering`。默认 `AUDIT_EXPORT_MAX_ROWS=10000`；查询 `limit + 1` 行，超限返回 400 `export_too_large`，details 只含 `count` 与 `limit`。

CSV 固定列为：`created_at`、`actor_username`、`action`、`resource_type`、`resource_id`、`resource_label`、`source`、`request_id`、`changes`。使用 UTF-8 BOM、标准 `csv.writer`、CRLF 与稳定排序 JSON。所有文本值若以 `= + - @ TAB CR LF` 开头，前置单引号，防止 Excel/CSV 公式注入。文件名只使用服务端 UTC 时间。

成功导出后记录 `audit_exported`，changes 仅保存规范化过滤摘要、行数和 `csv` 格式。无权限、校验失败或超限不记录成功审计。导出 queryset 在记录自身审计前完成，因此导出文件不包含本次导出事件。

### 归档模型与文件合同

新增 `AuditArchiveBatch`：UUID、状态、cutoff、首末事件时间、事件数、安全文件名、SHA-256、HMAC-SHA256、key ID、创建/完成时间与安全 failure code。它只记录归档元数据，不改变 `AuditEvent` 不可变约束。

`archive_audit_events` 默认 dry-run；只有显式 `--execute` 写文件。输出目录必须是已存在或可创建的仓库外绝对路径，解析后不得位于 Git 根目录内。命令按 `(created_at, id)` iterator 写临时 gzip JSONL，flush/fsync 后计算 SHA-256；manifest 使用 canonical JSON（不含 `hmac` 字段）计算 HMAC-SHA256，从而同时保护归档摘要和全部 manifest 元数据。归档与 manifest 在验证成功后用原子 rename 就位，不覆盖已有文件。

manifest schema version 1，包含 batch ID、UTC 时间范围、event count、安全文件名、SHA-256、HMAC 算法/key ID/HMAC、应用版本和完整 Git SHA；不包含密钥或绝对路径。

`verify_audit_archive` 验证安全相对文件名、路径边界、SHA-256、manifest HMAC、gzip、每行 JSON、事件 ID 唯一性、稳定排序、行数和时间范围。任一失败非零退出，且不输出归档内容。

### HMAC 密钥

归档只使用独立 `AUDIT_ARCHIVE_HMAC_ACTIVE_KID` 与 `AUDIT_ARCHIVE_HMAC_KEYS_JSON`，不复用 Django、JWT、账号 Token、数据库或 SMTP 密钥。dry-run 在没有 key 时可执行；`--execute` 和 verify 必须找到 manifest 指定 key ID。

### 保留策略

新增 `AUDIT_RETENTION_DAYS`，安全默认 0 表示无限期保留。`audit_retention_report` 只输出策略、总量、最早/最新时间、超过期限候选数、completed batch 数与未归档候选数。completed batch 的 cutoff 代表该时点之前的完整集合；命令不展示事件内容。

第四阶段不实现任何 purge、DELETE 或定时清理。未来物理清理必须具备明确公司期限、归档介质、成功完整性验证、备份恢复验证、双人审批和单独用户授权。

## Flutter 导出

复用唯一 Dio。`AuditExportRepository` 下载 CSV 字节并读取 `Content-Disposition` 安全文件名；字节只在 controller/repository 调用链中短暂存在，不放入 Widget 状态或日志。`AuditExportSaver` 负责平台保存：Windows 使用 Flutter 官方 `file_selector` Save dialog；Android 官方支持矩阵不支持 save-location，因此使用系统目录选择器，并在用户选择目录下以服务端安全文件名保存。取消返回安全取消结果，不申请广泛存储权限。

导出入口仅在 `can_export_audit` 时显示，提交前展示筛选摘要与确认。测试注入 Fake Repository/Saver，不弹系统窗口或写用户目录。

官方依赖依据：<https://pub.dev/packages/file_selector>（1.1.0，flutter.dev；Windows 支持 Save location，Android 支持目录选择但不支持 Save location）。

## 结果与限制

- 审计可导出、归档、验证和报告，但数据库记录不减少。
- 文件 HMAC 只能证明持有约定 key 的系统生成/验证过 manifest；密钥托管、离线介质和法定期限仍是外部决策。
- 本地验证归档不是正式生产归档或法律合规证明。
