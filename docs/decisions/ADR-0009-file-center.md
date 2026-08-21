# ADR-0009：员工附件文件中心与本地文件存储

- 状态：Accepted
- 日期：2026-08-20
- 适用阶段：第六阶段第一部分文件中心与员工附件

## 背景

第五阶段已将员工目录提升为企业工作台，但员工档案仍只能保存结构化字段，不能管理 PDF、Office 文档或图片附件。第六阶段第一部分需要支持员工附件的上传、列表、下载和软删除，同时继续使用 Django 模块化单体、现有 RBAC/审计体系和 Flutter feature-first 架构。本阶段只使用企业内部本地存储，不接入 OSS、S3、CDN、外部文件服务、消息队列或第二套认证体系。

## 决策

### 模块归属

采用方案 A：`EmployeeAttachment` 属于现有 `employees` Django app。实现文件放在 `modules/employees/attachments/` 包内，由 `employees.models` 导入模型以保持 Django 模型发现和 migration app label 不变。不创建独立 `files` app，不使用 GenericForeignKey。

员工附件当前只从属于 Employee，嵌套路由、对象权限和审计都以 Employee 为边界。只有未来文件需要同时关联合同、资产、公告等多个业务聚合时，才通过新的 ADR 评估独立文件模块。

### EmployeeAttachment 模型

模型字段为：

- UUID `id`。
- `employee`：`ForeignKey(Employee, PROTECT)`。
- `filename`：服务端生成的内部文件名 `<attachment_uuid>.<extension>`。
- `original_filename`：去除目录、控制字符并限制长度后的用户可见名称。
- `file_type`：`pdf/docx/xlsx/jpg/png` 固定枚举。
- `file_size`：正整数 bytes，数据库约束为 `1..10*1024*1024`。
- `storage_path`：相对于附件 storage root 的路径，唯一且不通过 API 返回。
- `uploaded_by`：`ForeignKey(User, SET_NULL, nullable)`。
- `created_at`、`updated_at`。
- `deleted_at`：可空软删除时间。

默认按 `-created_at, -id` 排序，并为 `(employee, deleted_at, created_at)` 建索引。数据库不保存文件内容，不增加 BinaryField。重复原始文件名允许存在，物理文件名始终由附件 UUID 隔离。

### 本地存储根与路径

使用专用 Django `FileSystemStorage`，配置项为 `EMPLOYEE_ATTACHMENT_STORAGE_ROOT`：

- 本地直接开发默认 `<repository>/storage/employee-attachments`，`storage/` 必须 Git ignore。
- Docker development/production 使用 `/data/employee-attachments` 持久化 volume。
- production 必须显式提供仓库外绝对路径；镜像内挂载根以 UID/GID `10001`、mode `0700` 创建，目录只允许该非 root 服务身份读写。

服务端只生成相对路径：

```text
employee/<employee_uuid>/<attachment_uuid>.<canonical_extension>
```

客户端不能提交 `filename`、`storage_path`、employee 或 uploaded_by。所有保存、打开、删除操作都在解析后的 storage root 边界内执行；绝对路径、storage root 和异常堆栈不得进入 API 或日志。

### 文件安全

单文件大小必须满足 `1 <= size <= 10 MiB`。允许 PDF、DOCX、XLSX、JPG/JPEG、PNG；拒绝 EXE、BAT、JS、APK、ZIP 和其他类型。

验证同时检查规范化扩展名和内容特征：

- PDF 检查 `%PDF-`。
- JPEG/PNG 检查文件签名。
- DOCX/XLSX 使用 Python 标准库 `zipfile` 检查 OOXML `[Content_Types].xml` 与 `word/` 或 `xl/` 结构。
- 普通 ZIP 即使可解压也拒绝。

原始文件名只取 basename，去除控制/格式字符和响应头危险字符，并按 Unicode code point 限制为 255 字符。实际或 RFC 5987 解码后的 `/`、`\` 仍视为路径分隔符并拒绝；basename 内不含分隔符的连续点（例如 `合同..😀.docx`）不是路径穿越，服务端和客户端均接受。稳定错误码包括 `attachment_type_not_allowed`、`attachment_too_large`、`attachment_invalid_content` 和 `attachment_file_missing`。

### 写入、软删除与下载

上传顺序为：权限校验、文件验证、生成 UUID/路径、写入专用 storage、transaction 内创建模型和审计。模型或审计失败时删除刚写入的孤立文件。

DELETE 只设置 `deleted_at` 并记录审计，不授予或执行数据库/磁盘物理删除。已软删除附件不能列表或下载。物理文件保留期限和清理任务不在本阶段实现，未来需独立保留/备份/恢复决策。

下载通过 `FileResponse` 流式返回，不把文件整体载入 Django 内存。响应使用清理后的原文件名、固定类型对应的 Content-Type、`X-Content-Type-Options: nosniff` 和私有非缓存策略。越权、已删除和不存在对象不泄露存在性；物理文件缺失返回稳定安全错误。

### 权限模型

继续使用 Django Group/model permissions，并增加对象级 queryset 过滤：

- employee 获得 `view_employeeattachment`，仅能列表和下载自身 Employee profile 的附件；无 Employee profile 时不能访问。
- hr_admin 获得 `view/add/change_employeeattachment`，可管理所有未关联 system_admin 的员工附件。
- system_admin 可管理全部员工附件。
- 不授予 `delete_employeeattachment`；软删除使用 `change_employeeattachment`。

除超级用户和 system_admin 角色外，任何列表或下载在进入本人/HR 对象范围前都必须先具有 `view_employeeattachment`。缺少读取动作权限返回 403；已具备读取动作权限但目标超出对象范围时返回安全 404。`add`/`change` 不能替代 `view`，管理动作仍按自身 model permission 独立判定。

HR 部门作用域本阶段不实现，只记录为未来设计。所有 list/detail/download/delete 都同时执行 queryset 过滤和对象权限，跨用户访问返回安全 404。Flutter 只根据当前 `employeeId` 和现有管理 capability 控制入口，后端是最终授权。

### API

新增：

- `GET /api/v1/employees/{employee_id}/attachments/`：受限分页列表。
- `POST /api/v1/employees/{employee_id}/attachments/`：multipart 字段 `file`，成功 201。
- `GET /api/v1/attachments/{attachment_id}/download/`：授权后的流式下载。
- `DELETE /api/v1/attachments/{attachment_id}/`：软删除，成功 204。

列表沿用 `count/next/previous/results` 分页合同。API 返回用户可见 filename、规范类型、整数 file_size、uploaded_by 安全摘要和 created_at，不返回 storage_path 或内部绝对路径。

### 审计

AuditEvent 增加 action：

- `employee_attachment.create`
- `employee_attachment.delete`

`resource_type=employee_attachment`，resource ID 为附件 UUID，resource label 为清理后的原始文件名。changes 白名单只增加 `filename`、`file_type`、`file_size`，员工使用既有安全 `employee_no` 表达；uploaded_by 由 actor 表达，时间由 AuditEvent.created_at 表达。

审计不得包含文件内容、storage_path、绝对路径、multipart 数据或下载字节。附件模型创建/软删除与 AuditEvent 在同一数据库 transaction 内完成。

### Flutter

新增 `features/attachments/`，继续使用现有 Riverpod、Dio、go_router 和 `file_selector`：

- data：attachment 模型、分页、repository。
- presentation：controller、员工详情附件区域、附件页面和上传页面。
- platform：文件选择和下载保存边界。

附件 controller 保留 `count`、已加载页码、`hasNext` 和 load-more 状态；用户可显式加载第 2 页及以后。跨页合并按服务端 `-created_at, -id` 顺序确定性去重，上传/删除后的刷新保留已加载深度，且不会隐藏旧页项目或复活本次已删除项目。下载 repository 必须接收规范 `file_type`，在响应文件名缺失或被安全策略拒绝时使用类型正确的 `attachment.<canonical_extension>` fallback。

扩展唯一 ApiClient，增加 multipart upload、DELETE 和安全通用二进制下载；不创建第二套 HTTP client。已有 CSV 下载接口保持兼容。

员工只能在自己的详情看到附件入口；HR/system 管理入口由现有管理 capability 控制，后端仍重新授权。页面必须覆盖 loading、empty、error、retry、success，上传按钮在请求期间禁用以防重复提交。客户端只做类型/大小预检查，服务端验证为最终权威。

Android `ACTION_CREATE_DOCUMENT` 接受 URI 后的写入不得因 Flutter engine teardown 被 `shutdownNow` 中断。chooser 阶段可取消；writing 阶段由 executor 完成写入并在 teardown 后抑制回调，写入失败时只对本次创建的 document URI 做 best-effort delete。真实慢速 provider 仍需受控设备验证。

### 性能与查询

附件 endpoint 使用 `select_related(employee, uploaded_by)`，按单员工与未删除条件查询并分页。员工详情的附件区域独立加载，不在 10,000 员工目录查询中预取全部附件。测试必须证明列表查询数不随附件数量增长，不产生 uploaded_by N+1。

## 测试策略

后端按 TDD 覆盖模型约束、软删除、权限矩阵、类型/大小/内容签名、路径穿越、文件名/Content-Disposition、孤立文件清理、list/upload/download/delete、审计和常量查询数。文件测试使用临时 storage root，不写真实 storage。SQLite、PostgreSQL 和 Strict OpenAPI 使用同一 migration/API 合同。

Flutter按 TDD 覆盖 JSON/分页、跨页加载与变更刷新、multipart upload、所有允许 MIME 的类型正确 fallback、DELETE、错误映射、controller 状态与重复提交保护，以及列表空态、错误重试、上传预览/成功、下载取消和权限入口。Android 另用无新依赖的 Kotlin 生命周期契约覆盖 writing teardown、回调抑制和失败清理；完成前验证 Windows/Android Debug build 与 `scripts/check.ps1`。

## 结果与限制

- 本阶段形成 Employee 专属的内部附件资料中心，不形成通用文件平台。
- 不支持对象存储、CDN、外链分享、文件版本、在线预览、病毒扫描服务、OCR、全文检索或自动物理清理。
- 本地存储的备份、保留期限和未来 HR 部门作用域必须在正式部署前另行决策。
