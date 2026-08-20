# 审计导出、归档与保留治理

## CSV 导出

- 端点：`GET /api/v1/audit-events/export.csv`。
- 权限：Django `audit.export_auditevent`，只由 system_admin 持有；anonymous 为 401，employee/hr_admin 为 403。
- 筛选：`actor`、`action`、`resource_type`、`resource_id`、`created_after`、`created_before` 和白名单 `ordering`。
- 上限：`AUDIT_EXPORT_MAX_ROWS=10000`；超过返回 `export_too_large`，不返回样本。
- 格式：固定列、UTC ISO 8601、稳定排序 JSON、UTF-8 BOM、CRLF、标准 CSV writer。
- 公式防护：文本首字符为 `= + - @ Tab CR LF` 时增加单引号。
- 成功导出写入 `audit_exported`，只记录过滤摘要、行数和格式；失败或无权限不写成功审计。

Flutter 入口仅在 `/me` 的 `can_export_audit=true` 时显示，后端权限仍是权威。Windows 使用系统 Save 对话框；Android 使用系统目录选择器与服务器安全文件名，不申请广泛存储权限。

## 非破坏性归档

`archive_audit_events` 默认 dry-run；`--execute` 才写 gzip JSONL 和 manifest。事件按 `(created_at, id)` 排序，使用 iterator、同目录临时文件、flush/fsync、自验证和原子 rename。输出目录必须是仓库外绝对路径，已有目标不会覆盖。

manifest schema 1 包含 batch、时间范围、事件数量、文件名、SHA-256、HMAC-SHA256、key ID、应用版本和完整 Git SHA，不包含 key 或事件内容。`verify_audit_archive` 同时检查：

- 文件与安全文件名；
- manifest HMAC 与归档 SHA-256；
- gzip/UTF-8 JSONL 可读性；
- 行数、首末时间、稳定顺序和 ID 唯一性。

示例：

```powershell
python manage.py archive_audit_events `
  --before 2026-01-01T00:00:00Z `
  --output-dir D:\EmployeeAuditArchives\Validation `
  --dry-run

python manage.py verify_audit_archive `
  --manifest D:\EmployeeAuditArchives\Validation\<safe-manifest>.json
```

不得在命令行或文档中放 HMAC key。归档文件、manifest 和 CSV 不进入 Git。

## 保留

`AUDIT_RETENTION_DAYS=0` 表示无限期保留。`audit_retention_report` 只输出总量、时间范围、候选量、已完成批次和未归档候选量，不输出事件内容。

本阶段没有 `purge_audit_events`、DELETE、定时清理或数据库直接清理。未来物理清理至少要求：公司明确法定期限、归档介质确定、HMAC 验证成功、备份恢复验证、双人审批和新的明确用户授权。

## 2026-08-20 本地证据

经用户明确授权，50 条开发数据库审计事件被归档到仓库外目录；SHA/HMAC/事件数验证通过，篡改一字节的副本被拒绝并删除，`AuditEvent` 数量前后均为 50。有效归档保留；验收 HMAC key 只存在于执行进程，没有持久化，因此未来再次 HMAC 验证必须由授权方重新提供同一 key。
