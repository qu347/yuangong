# 员工附件存储运维指南

本指南说明 ADR-0009 已实现的本地文件存储合同。文件中心只服务 Employee 附件，不是通用文件平台。

## 存储合同

- Django 使用独立 `FileSystemStorage`，根目录由 `EMPLOYEE_ATTACHMENT_STORAGE_ROOT` 提供。
- 本地开发默认使用仓库内已忽略的 `storage/employee-attachments`；不得提交其中任何文件。
- production 必须显式配置仓库外绝对目录，且不能与 `AUDIT_ARCHIVE_DIR` 相同。
- Docker development/production 的容器内挂载点为 `/data/employee-attachments`，Compose 默认使用持久 named volume `attachment_data`。
- Django 上传文件权限为 `0600`，自动创建目录权限为 `0700`。production 镜像也以 UID/GID `10001`、mode `0700` 创建挂载根；只有 production 容器承诺服务进程以该非 root 身份运行，development 容器不提供 UID/GID `10001` 身份保证。

服务端生成的相对路径固定为：

```text
employee/<employee_uuid>/<attachment_uuid>.<canonical_extension>
```

内部文件名固定为 `<attachment_uuid>.<canonical_extension>`。UUID 和规范扩展名均由服务端产生；原始文件名只用于安全展示与下载响应。API、日志和审计不得暴露 storage root、`storage_path` 或解析后的绝对路径。

## Production Docker 所有权

production 镜像在切换为非 root 用户前以 `install -d -m 0700 -o app -g app` 创建挂载点。首次把全新空 named volume 挂到 production 镜像的该位置时，Docker 会执行 copy-up，目录所有权和 mode 随镜像目录进入 volume。本轮针对 production image 使用一次性空 named volume 的新鲜探针得到 `COPY_UP_OWNER=10001:10001`、`COPY_UP_MODE=700`、`COPY_UP_WRITE=ok`；探针卷随后删除。

production bind mount 会覆盖镜像内目录，不能依赖 copy-up。选择 production bind mount 的运营方必须在启动 API 前创建宿主目录，并确保映射后 UID/GID `10001` 可读写；这是运营方责任。不要让 production 容器以 root 运行来规避权限错误，也不要放宽为全员可写。

development 镜像没有切换到 production 的 `app` 用户，因而不承诺 UID/GID `10001`，也不能用上述 production copy-up 探针推断其运行身份或宿主目录所有权。开发故障排查应以实际容器身份和开发 Compose 挂载为准。

## 类型、大小与内容校验

| 用户扩展名 | 规范类型 | 服务端内容检查 |
| --- | --- | --- |
| `.pdf` | `pdf` | `%PDF-` |
| `.docx` | `docx` | OOXML `[Content_Types].xml` 与 `word/document.xml` |
| `.xlsx` | `xlsx` | OOXML `[Content_Types].xml` 与 `xl/workbook.xml` |
| `.jpg` / `.jpeg` | `jpg` | JPEG 签名 |
| `.png` | `png` | PNG 签名 |

大小范围为 1 byte 至 10 MiB（`10 * 1024 * 1024` bytes，含上限）。普通 ZIP、伪装扩展、双扩展可执行文件、空文件和签名不匹配内容会被拒绝。原文件名只保留 basename，移除控制/格式字符和响应头危险字符，并按 Unicode code point 限制为 255 字符。实际或解码后的 `/`、`\` 被拒绝；不含分隔符的内部连续点（如 `合同..😀.docx`）合法。

## 权限矩阵

| 角色 | 列表/下载 | 上传 | 软删除 | 物理删除 |
| --- | --- | --- | --- | --- |
| employee | 仅本人 Employee profile | 否 | 否 | 否 |
| hr_admin | 除 system_admin/超级用户目标外 | 同左 | 同左 | 否 |
| system_admin / 超级用户 | 全部员工 | 全部员工 | 全部员工 | 否 |

软删除使用 `change_employeeattachment`，任何角色都不获得 `delete_employeeattachment`。缺少上传或软删除动作权限返回 403；目标超出对象范围、已软删除或不存在时返回安全 404。客户端入口隐藏不替代后端鉴权。

除 system_admin/超级用户外，列表与下载必须先有 `view_employeeattachment`。roleless linked user、只有 `add` 或只有 `change` 而没有 `view` 的账号均在进入本人/HR 范围前返回 403；已有 `view` 但访问范围外对象仍返回 404。

## 写入、审计与保留

上传先完成授权和内容验证，再生成 UUID/路径并写入 storage，随后在同一数据库事务内创建 `EmployeeAttachment` 和 `employee_attachment.create` 审计。如果元数据或审计提交失败，只清理本次新写入的孤立文件。

软删除在行锁保护的数据库事务内写入 `deleted_at` 并记录 `employee_attachment.delete`，不会调用 storage delete。当前没有物理清理、附件恢复或保留期任务；因此软删除文件继续占用容量。正式部署前必须确定容量告警、法定保留期、清理审批和恢复授权。

`employee_attachment.create` 的 `changes` 精确包含 `employee_no`、清理后的 `filename`、规范 `file_type` 和 `file_size`；`employee_attachment.delete` 的 `changes` 只包含清理后的 `filename`。两类事件都通过 AuditEvent 元数据记录附件 resource UUID、resource label、actor 和时间；都不记录文件字节、multipart 内容、`storage_path` 或绝对路径。

## 备份与恢复

数据库元数据和附件文件必须作为同一个恢复点管理。运营方应：

1. 对 PostgreSQL 与附件存储做协调快照或记录可重放的一致性边界。
2. 备份 named volume 或 bind-mount 宿主目录，并加密、限制访问、监控容量和定期验证恢复。
3. 恢复时保持服务端相对路径、文件内容和数据库 `storage_path` 一致，并恢复私有权限；production 部署还必须恢复 UID/GID `10001`。
4. 在隔离环境抽样验证授权下载；不要用真实员工文件做开发测试。

只备份数据库会留下无法下载的元数据；只备份文件会留下无法授权、无法审计的孤立内容。本阶段未实现应用层校验和清单或自动备份。

## 物理文件缺失处理

当数据库存在活动元数据但 storage 中的物理文件缺失时，下载返回 `404 / attachment_file_missing`，不会暴露路径。排障流程：

1. 根据安全监控确认挂载存在、容量和 UID/GID 权限正常；不要把绝对路径贴入工单、聊天或日志。
2. 依据同一恢复点的备份，把正确文件恢复到元数据记录的相对路径，并恢复私有权限。
3. 用具备对象权限的测试账号重新请求下载，确认类型、文件名和内容正确。
4. 无可用备份时保留元数据与审计，按事故流程登记数据丢失；不要伪造空文件、直接改库或通过重传同名文件假装恢复。

物理文件恢复不会自动产生附件 create/delete 审计；运营恢复操作应进入独立运维审计。本阶段没有自助恢复端点。

## 客户端保存边界

Windows 使用系统文件选择/保存能力。Android 下载保存由应用自有平台通道发起 `ACTION_CREATE_DOCUMENT`，通过 `ContentResolver` 写入用户选择的 document URI；写入在单线程 `ExecutorService` 上执行，不使用或返回原始文件系统路径。Flutter engine teardown 只取消仍在 chooser 阶段的请求；已接受 URI 的写入使用 orderly shutdown 完成，teardown 后抑制 MethodChannel 回调，写入失败时对本次 URI 做 best-effort delete。

本阶段已覆盖 Dart 平台边界测试、无新依赖的 Kotlin writing-teardown/cleanup contract，以及 Android/Windows Debug 构建。真实 Android 慢速 document provider instrumentation 仍需要受控设备/provider；当前约束下未引入额外依赖，详见文件中心验收报告的警告。
