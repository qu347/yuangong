# 第六阶段第一部分文件中心实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 employees Django app 和 Flutter feature-first 架构内交付安全的员工附件上传、列表、下载与软删除能力。

**Architecture:** `EmployeeAttachment` 归属 `employees` app，文件本体由专用本地 `FileSystemStorage` 保存，数据库只保存安全元数据和相对路径。后端使用现有 Group/model permissions、对象级 queryset 过滤和 AuditEvent；Flutter 扩展唯一 ApiClient，并复用 Riverpod、go_router、Dio 与 file_selector。

**Tech Stack:** Django 5.2、Django REST Framework、PostgreSQL、SQLite、pytest、Flutter 3.47、Dart 3.13、Riverpod、go_router、Dio、file_selector。

**Spec:** `docs/decisions/ADR-0009-file-center.md`

## Global Constraints

- 仅支持 Windows 与 Android；不得创建 iOS、Web、macOS 或 Linux 业务实现。
- 不新增 Django app、微服务、消息队列、对象存储、CDN、外部文件服务或第二套认证体系。
- 不修改第五阶段历史，不修改 `docs/environment-configuration.md`。
- 不增加第三方依赖；DOCX/XLSX 内容检查使用 Python 标准库 `zipfile`。
- 文件内容不得进入数据库、审计、日志或错误响应。
- 所有行为先观察目标测试因缺少能力而失败，再写最小实现。
- Git commit 只有获得用户明确授权后才执行；计划中的 commit 命令仅表示建议边界。

---

## 文件结构

```text
backend/modules/employees/attachments/
    __init__.py                 # 附件包边界
    exceptions.py               # 稳定附件错误码
    models.py                   # EmployeeAttachment
    permissions.py              # 角色/对象可见范围
    serializers.py              # 列表与上传响应
    services.py                 # 上传、软删除、审计、失败清理
    storage.py                  # 专用 FileSystemStorage 与安全相对路径
    urls.py                     # nested/list/upload/download/delete routes
    validation.py               # 文件名、大小、扩展名和内容签名
    views.py                    # HTTP/multipart/FileResponse 边界

apps/employee_app/lib/features/attachments/
    data/attachment.dart
    data/attachment_repository.dart
    platform/attachment_file_picker.dart
    platform/attachment_file_saver.dart
    presentation/attachment_controller.dart
    presentation/attachment_page.dart
    presentation/attachment_upload_controller.dart
    presentation/attachment_upload_page.dart
    presentation/employee_attachment_section.dart
```

## Task 1：本地存储配置合同

**Files:**

- Modify: `backend/config/settings/base.py`
- Modify: `backend/config/settings/production.py`
- Modify: `backend/tests/test_production_settings.py`
- Modify: `backend/tests/test_production_compose.py`
- Modify: `deploy/docker-compose.dev.yml`
- Modify: `deploy/docker-compose.production.example.yml`
- Modify: `deploy/backend/Dockerfile.production`
- Modify: `.env.example`
- Modify: `.gitignore`
- Test: `backend/tests/test_attachment_storage_settings.py`

**Interfaces:**

- Consumes: `PROJECT_ROOT` and existing production `invalid()` contract.
- Produces: `EMPLOYEE_ATTACHMENT_STORAGE_ROOT: Path` and `EMPLOYEE_ATTACHMENT_MAX_BYTES = 10 * 1024 * 1024`.

- [x] **Step 1: Write failing settings tests**

```python
def test_test_settings_use_ignored_local_attachment_root(settings):
    assert settings.EMPLOYEE_ATTACHMENT_MAX_BYTES == 10 * 1024 * 1024
    assert settings.EMPLOYEE_ATTACHMENT_STORAGE_ROOT.name == "employee-attachments"


def test_production_rejects_attachment_root_inside_repository():
    environment = valid_production_environment()
    environment["EMPLOYEE_ATTACHMENT_STORAGE_ROOT"] = str(REPOSITORY_ROOT / "storage")
    result = run_production_import(environment)
    assert result.returncode != 0
    assert "outside the repository" in result.stderr
```

- [x] **Step 2: Verify RED**

Run: `backend\.venv\Scripts\python.exe -m pytest -q tests\test_attachment_storage_settings.py tests\test_production_settings.py tests\test_production_compose.py`

Expected: FAIL because the attachment root and Docker volume contract do not exist.

- [x] **Step 3: Implement the configuration contract**

```python
# config/settings/base.py
EMPLOYEE_ATTACHMENT_MAX_BYTES = 10 * 1024 * 1024
EMPLOYEE_ATTACHMENT_STORAGE_ROOT = Path(
    env(
        "EMPLOYEE_ATTACHMENT_STORAGE_ROOT",
        default=str(PROJECT_ROOT / "storage" / "employee-attachments"),
    )
).resolve()
FILE_UPLOAD_PERMISSIONS = 0o600
FILE_UPLOAD_DIRECTORY_PERMISSIONS = 0o700
```

Production must read the variable without a default, require an absolute repository-external path, and reject equality with `AUDIT_ARCHIVE_DIR`. Compose must mount `attachment_data:/data/employee-attachments`; Dockerfile.production must create the directory as UID/GID 10001 with mode `0700`. Add `/storage/` to `.gitignore`.

- [x] **Step 4: Verify GREEN**

Run the Step 2 command and `docker compose -f deploy/docker-compose.production.example.yml config --quiet` with the same safe test environment used by existing compose tests.

- [ ] **Step 5: Suggested commit boundary**

```text
build: add local attachment storage contract
```

## Task 2：EmployeeAttachment 模型、RBAC 与审计动作

**Files:**

- Create: `backend/modules/employees/attachments/__init__.py`
- Create: `backend/modules/employees/attachments/models.py`
- Modify: `backend/modules/employees/models.py`
- Modify: `backend/modules/employees/admin.py`
- Create: `backend/modules/employees/migrations/0003_employeeattachment.py`
- Modify: `backend/modules/accounts/rbac.py`
- Modify: `backend/modules/audit/models.py`
- Modify: `backend/modules/audit/services.py`
- Create: `backend/modules/audit/migrations/0005_attachment_audit_actions.py`
- Test: `backend/tests/test_employee_attachment_model.py`
- Test: `backend/tests/test_rbac.py`
- Test: `backend/tests/test_audit_api.py`

**Interfaces:**

- Produces: `EmployeeAttachment`, `AuditEvent.Action.EMPLOYEE_ATTACHMENT_CREATE`, `AuditEvent.Action.EMPLOYEE_ATTACHMENT_DELETE`.
- Produces permissions: employee `view`; HR/system `view/add/change`; no role receives physical delete.

- [x] **Step 1: Write failing model/RBAC/audit tests**

```python
@pytest.mark.django_db
def test_attachment_model_keeps_only_safe_metadata(employee, user):
    attachment = EmployeeAttachment.objects.create(
        employee=employee,
        filename="00000000-0000-0000-0000-000000000901.pdf",
        original_filename="合同.pdf",
        file_type="pdf",
        file_size=1024,
        storage_path=f"employee/{employee.id}/00000000-0000-0000-0000-000000000901.pdf",
        uploaded_by=user,
    )
    assert attachment.deleted_at is None
    assert not any(isinstance(field, models.BinaryField) for field in attachment._meta.fields)


def test_attachment_roles_never_receive_physical_delete_permission():
    call_command("sync_rbac")
    hr_permissions = set(Group.objects.get(name="hr_admin").permissions.values_list("codename", flat=True))
    assert {"view_employeeattachment", "add_employeeattachment", "change_employeeattachment"} <= hr_permissions
    assert "delete_employeeattachment" not in hr_permissions
```

- [x] **Step 2: Verify RED**

Run: `backend\.venv\Scripts\python.exe -m pytest -q tests\test_employee_attachment_model.py tests\test_rbac.py tests\test_audit_api.py`

Expected: collection/test failure because EmployeeAttachment and attachment audit actions do not exist.

- [x] **Step 3: Implement model and choices**

```python
class EmployeeAttachment(models.Model):
    class FileType(models.TextChoices):
        PDF = "pdf", "PDF"
        DOCX = "docx", "DOCX"
        XLSX = "xlsx", "XLSX"
        JPG = "jpg", "JPG"
        PNG = "png", "PNG"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    employee = models.ForeignKey("employees.Employee", on_delete=models.PROTECT, related_name="attachments")
    filename = models.CharField(max_length=255)
    original_filename = models.CharField(max_length=255)
    file_type = models.CharField(max_length=8, choices=FileType.choices)
    file_size = models.PositiveBigIntegerField()
    storage_path = models.CharField(max_length=500, unique=True)
    uploaded_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="uploaded_employee_attachments")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)
```

Add a named size CheckConstraint, ordering and `(employee, deleted_at, created_at)` index. Import the class at the bottom of `employees.models`. Add audit actions with exact values `employee_attachment.create` and `employee_attachment.delete`; extend safe audit change fields with `filename`, `file_type`, `file_size`.

- [x] **Step 4: Generate and verify migrations**

Run:

```powershell
backend\.venv\Scripts\python.exe backend\manage.py makemigrations employees audit --settings=config.settings.test
backend\.venv\Scripts\python.exe backend\manage.py makemigrations --check --dry-run --settings=config.settings.test
```

Expected final output: `No changes detected`.

- [x] **Step 5: Verify GREEN**

Run the Step 2 command.

- [ ] **Step 6: Suggested commit boundary**

```text
feat: add employee attachment model and permissions
```

## Task 3：文件名、类型、内容签名与 storage 边界

**Files:**

- Create: `backend/modules/employees/attachments/exceptions.py`
- Create: `backend/modules/employees/attachments/storage.py`
- Create: `backend/modules/employees/attachments/validation.py`
- Test: `backend/tests/test_employee_attachment_security.py`

**Interfaces:**

- Produces: `ValidatedAttachment(original_filename, file_type, file_size)`.
- Produces: `validate_attachment(uploaded_file)`, `attachment_storage_path(employee_id, attachment_id, file_type)`, `get_attachment_storage()`.

- [x] **Step 1: Write failing security tests**

```python
@pytest.mark.parametrize("name", ["run.exe", "script.js", "archive.zip", "app.apk"])
def test_attachment_validation_rejects_forbidden_extensions(name):
    upload = SimpleUploadedFile(name, b"forbidden")
    with pytest.raises(AttachmentRequestError) as error:
        validate_attachment(upload)
    assert error.value.error_code == "attachment_type_not_allowed"


def test_attachment_path_ignores_client_directories(employee):
    validated = validate_attachment(SimpleUploadedFile("../../合同.pdf", b"%PDF-1.7\n"))
    path = attachment_storage_path(employee.id, UUID("00000000-0000-0000-0000-000000000901"), validated.file_type)
    assert path == f"employee/{employee.id}/00000000-0000-0000-0000-000000000901.pdf"
    assert ".." not in path
```

Create literal valid fixtures for PDF, JPEG, PNG and minimal DOCX/XLSX OOXML ZIP containers. Test zero bytes, exact 10 MiB, 10 MiB + 1, mixed-case extensions, double extensions, mismatched signatures, control characters and ordinary ZIP rejection.

- [x] **Step 2: Verify RED**

Run: `backend\.venv\Scripts\python.exe -m pytest -q tests\test_employee_attachment_security.py`

Expected: import/test failure because validation and storage functions do not exist.

- [x] **Step 3: Implement stable request errors**

```python
class AttachmentRequestError(APIException):
    status_code = status.HTTP_400_BAD_REQUEST

    def __init__(self, message, *, code):
        super().__init__(message, code=code)
        self.error_code = code


class AttachmentFileMissing(APIException):
    status_code = status.HTTP_404_NOT_FOUND
    default_detail = "附件文件不存在。"
    default_code = "attachment_file_missing"
    error_code = "attachment_file_missing"
```

- [x] **Step 4: Implement validation and storage helpers**

`validate_attachment()` must normalize extension, sanitize basename, check `uploaded_file.size`, inspect the first bytes/OOXML members, restore the stream position to zero, and return a frozen dataclass. `attachment_storage_path()` must return a `PurePosixPath`-derived relative string using only server UUIDs and canonical extension. `get_attachment_storage()` must construct `FileSystemStorage(location=settings.EMPLOYEE_ATTACHMENT_STORAGE_ROOT)`.

- [x] **Step 5: Verify GREEN**

Run the Step 2 command; all file fixtures must use `tmp_path` or in-memory uploaded files.

- [ ] **Step 6: Suggested commit boundary**

```text
feat: validate and store employee attachment files safely
```

## Task 4：对象权限、上传服务与列表/上传 API

**Files:**

- Create: `backend/modules/employees/attachments/permissions.py`
- Create: `backend/modules/employees/attachments/services.py`
- Create: `backend/modules/employees/attachments/serializers.py`
- Create: `backend/modules/employees/attachments/views.py`
- Create: `backend/modules/employees/attachments/urls.py`
- Modify: `backend/modules/employees/urls.py`
- Test: `backend/tests/test_employee_attachment_api.py`
- Test: `backend/tests/test_employee_attachment_permissions.py`

**Interfaces:**

- Produces: `visible_attachments(user)`, `get_visible_employee(user, employee_id, manage=False)`, `create_attachment(employee, actor, uploaded_file, request_id=None)`.
- Produces: GET/POST `/api/v1/employees/{employee_id}/attachments/`.

- [x] **Step 1: Write failing permission and upload tests**

```python
@pytest.mark.django_db
def test_employee_lists_only_own_attachments(employee_client, own_employee, other_attachment):
    response = employee_client.get(f"/api/v1/employees/{own_employee.id}/attachments/")
    assert response.status_code == 200
    assert all(item["employee_id"] == str(own_employee.id) for item in response.json()["results"])
    assert employee_client.get(f"/api/v1/employees/{other_attachment.employee_id}/attachments/").status_code == 404


def test_hr_upload_records_metadata_and_audit(hr_client, employee, valid_pdf, settings):
    response = hr_client.post(
        f"/api/v1/employees/{employee.id}/attachments/",
        {"file": valid_pdf},
        format="multipart",
    )
    assert response.status_code == 201
    assert response.json()["filename"] == "合同.pdf"
    assert "storage_path" not in response.json()
    assert AuditEvent.objects.get(resource_id=response.json()["id"]).action == "employee_attachment.create"
```

Cover employee upload denial, HR non-system target access, HR system-admin target hiding, system full access, missing Employee profile and uploaded_by summary without token/path fields.

- [x] **Step 2: Verify RED**

Run: `backend\.venv\Scripts\python.exe -m pytest -q tests\test_employee_attachment_permissions.py tests\test_employee_attachment_api.py -k "list or upload"`

Expected: route/import failure because the attachment permission/service/API does not exist.

- [x] **Step 3: Implement visible scopes**

```python
def visible_attachments(user):
    base = EmployeeAttachment.objects.filter(deleted_at__isnull=True).select_related(
        "employee", "employee__user", "uploaded_by"
    )
    if is_system_admin(user):
        return base
    if not user.has_perm("employees.view_employeeattachment"):
        raise PermissionDenied()
    if user.has_perm("employees.add_employeeattachment") or user.has_perm(
        "employees.change_employeeattachment"
    ):
        return base.exclude(employee__user__groups__name=ROLE_SYSTEM_ADMIN).exclude(
            employee__user__is_superuser=True
        ).distinct()
    employee_id = getattr(getattr(user, "employee_profile", None), "id", None)
    return base.filter(employee_id=employee_id) if employee_id else base.none()
```

`get_visible_employee(..., manage=False)` must enforce the same view gate before own/HR object filtering; `manage=True` must independently require add/change permission and apply the same system-admin target exclusion. Missing read action permission is 403; an object outside an authorized scope is 404. Soft delete uses a separate manageable queryset so `change` does not silently substitute for `view` on reads.

- [x] **Step 4: Implement upload service with orphan cleanup**

Generate attachment UUID/path before writing. Save via dedicated storage, then create EmployeeAttachment and AuditEvent in one transaction. On any exception after storage save, delete only the generated saved path and re-raise. Audit changes are exactly employee_no, filename, file_type and file_size.

- [x] **Step 5: Implement paginated GET and multipart POST**

Use `ListCreateAPIView`, `DirectoryPagination`, `MultiPartParser` and `FormParser`. GET may view; POST must manage. Serializer exposes `id`, `employee_id`, display filename, file_type, integer file_size, uploaded_by `{id, username}`, created_at; internal filename/storage_path/deleted_at are not exposed.

- [x] **Step 6: Verify GREEN and constant queries**

Run the Step 2 command and assert the list endpoint query count is constant for 1 and 20 attachments with uploaded_by populated.

- [ ] **Step 7: Suggested commit boundary**

```text
feat: add attachment list and upload api
```

## Task 5：下载、软删除与 OpenAPI

**Files:**

- Modify: `backend/modules/employees/attachments/services.py`
- Modify: `backend/modules/employees/attachments/views.py`
- Modify: `backend/modules/employees/attachments/urls.py`
- Modify: `backend/tests/test_employee_attachment_api.py`
- Modify: `backend/tests/test_employee_attachment_security.py`
- Modify: `backend/tests/test_schema.py`

**Interfaces:**

- Produces: `soft_delete_attachment(attachment_id, actor, request_id=None)`.
- Produces: GET `/api/v1/attachments/{attachment_id}/download/` and DELETE `/api/v1/attachments/{attachment_id}/`.

- [x] **Step 1: Write failing download/delete tests**

```python
def test_download_streams_safe_file_without_exposing_path(employee_client, own_attachment):
    response = employee_client.get(f"/api/v1/attachments/{own_attachment.id}/download/")
    assert response.status_code == 200
    assert b"".join(response.streaming_content).startswith(b"%PDF-")
    assert response["X-Content-Type-Options"] == "nosniff"
    assert str(settings.EMPLOYEE_ATTACHMENT_STORAGE_ROOT) not in str(response.headers)


def test_delete_soft_deletes_and_keeps_file(hr_client, attachment, attachment_storage):
    response = hr_client.delete(f"/api/v1/attachments/{attachment.id}/")
    attachment.refresh_from_db()
    assert response.status_code == 204
    assert attachment.deleted_at is not None
    assert attachment_storage.exists(attachment.storage_path)
    assert AuditEvent.objects.get(resource_id=str(attachment.id)).action == "employee_attachment.delete"
```

Cover cross-user 404, employee DELETE denial, HR system-admin target 404, system success, deleted download 404, missing physical file stable error and Content-Disposition control-character safety.

- [x] **Step 2: Verify RED**

Run: `backend\.venv\Scripts\python.exe -m pytest -q tests\test_employee_attachment_api.py -k "download or delete" tests\test_employee_attachment_security.py`

Expected: 404/method failure because routes and service are absent.

- [x] **Step 3: Implement download boundary**

Fetch only through `visible_attachments(user)`. Verify storage existence, open in binary mode, and return `FileResponse(as_attachment=True, filename=original_filename, content_type=FILE_TYPE_CONTENT_TYPES[file_type])`. Set `Cache-Control: private, no-store` and `X-Content-Type-Options: nosniff`.

- [x] **Step 4: Implement transactional soft delete**

Lock an active attachment from the manageable scope, set `deleted_at=timezone.now()`, save only deleted_at/updated_at, and record `employee_attachment.delete` in the same transaction. Do not call storage.delete.

- [x] **Step 5: Document strict OpenAPI**

Use drf-spectacular annotations for multipart request, paginated metadata response, binary download and 204 delete. Add exact path assertions to `test_schema.py`.

- [x] **Step 6: Verify GREEN**

Run target tests and:

```powershell
backend\.venv\Scripts\python.exe backend\manage.py spectacular --validate --fail-on-warn --settings=config.settings.test --file "$env:TEMP\phase-six-attachments.yaml"
```

- [ ] **Step 7: Suggested commit boundary**

```text
feat: add authorized attachment download and soft delete
```

## Task 6：Flutter 通用二进制网络与附件 repository/platform

**Files:**

- Modify: `apps/employee_app/lib/core/network/api_client.dart`
- Modify: `apps/employee_app/lib/core/network/api_endpoints.dart`
- Create: `apps/employee_app/lib/features/attachments/data/attachment.dart`
- Create: `apps/employee_app/lib/features/attachments/data/attachment_repository.dart`
- Create: `apps/employee_app/lib/features/attachments/platform/attachment_file_picker.dart`
- Create: `apps/employee_app/lib/features/attachments/platform/attachment_file_saver.dart`
- Test: `apps/employee_app/test/core/network/api_client_file_test.dart`
- Test: `apps/employee_app/test/features/attachments/attachment_repository_test.dart`
- Test: `apps/employee_app/test/features/attachments/attachment_platform_test.dart`

**Interfaces:**

- Produces: `ApiFileDownload(bytes, filename, mimeType)`, `ApiClient.downloadFile(...)`, `ApiClient.deleteVoid(path)`.
- Produces: `AttachmentRepository.fetch/upload/download/delete`, with download receiving the expected canonical `file_type`; produces `AttachmentFilePicker`, `AttachmentFileSaver`.

- [x] **Step 1: Write failing ApiClient/repository tests**

```dart
test('attachment repository sends multipart file and parses safe metadata', () async {
  final attachment = await repository.uploadAttachment(
    employeeId,
    const AttachmentUploadCandidate(
      path: r'C:\temp\contract.pdf',
      name: 'contract.pdf',
      size: 1024,
      extension: 'pdf',
    ),
  );
  expect(attachment.filename, 'contract.pdf');
  expect(attachment.fileSize, 1024);
});


test('generic download rejects traversal filename from response headers', () async {
  final download = await client.downloadFile(
    'attachments/id/download/',
    fallbackFilename: 'attachment.pdf',
    allowedExtensions: const {'pdf'},
  );
  expect(download.filename, 'attachment.pdf');
});
```

Use real Dio MockAdapter/fake transport at the existing ApiClient boundary. Test DELETE 204, safe Unicode basename, extension allowlist and existing audit CSV download compatibility.

- [x] **Step 2: Verify RED**

Run: `flutter test test/core/network/api_client_file_test.dart test/features/attachments/attachment_repository_test.dart test/features/attachments/attachment_platform_test.dart`

Expected: compile failure because generic download/delete and attachment feature types do not exist.

- [x] **Step 3: Extend the single ApiClient**

```dart
class ApiFileDownload {
  const ApiFileDownload({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });
  final Uint8List bytes;
  final String filename;
  final String mimeType;
}
```

`downloadFile()` must use the existing authenticated Dio, ResponseType.bytes, safe Content-Disposition basename parsing and caller-provided extension allowlist. Internal consecutive dots without separators are allowed; actual/decoded separators and control/format characters remain rejected, and length uses Unicode scalars. `downloadBytes()` remains as the CSV-compatible wrapper. `deleteVoid()` maps errors through the existing `_mapDioException`.

- [x] **Step 4: Implement attachment repository**

Build `FormData` with one `MultipartFile.fromFile(candidate.path, filename: candidate.name)` and call existing `postMap`. List uses getMap pagination; download passes canonical `file_type` to choose `attachment.pdf/docx/xlsx/jpg/png` fallback before generic download; delete uses deleteVoid. Map stable attachment error codes to simplified Chinese Failures, including HTTP 400 `attachment_storage_conflict` as the retry-specific conflict message.

- [x] **Step 5: Implement platform picker/saver**

Picker uses file_selector `openFile` with PDF/DOCX/XLSX/JPG/JPEG/PNG groups, derives basename/extension/length and rejects unsupported or >10 MiB before upload. Saver mirrors the existing audit pattern: Windows save location, Android selected directory, cancellation as a non-error result. No iOS/Web/macOS/Linux branches beyond safe unsupported failure.

- [x] **Step 6: Verify GREEN**

Run the Step 2 command and existing audit export repository/saver/controller tests.

- [ ] **Step 7: Suggested commit boundary**

```text
feat: add flutter attachment data and file platform services
```

## Task 7：Flutter controller、附件页面、上传页面与员工详情集成

**Files:**

- Create: `apps/employee_app/lib/features/attachments/presentation/attachment_controller.dart`
- Create: `apps/employee_app/lib/features/attachments/presentation/attachment_page.dart`
- Create: `apps/employee_app/lib/features/attachments/presentation/attachment_upload_controller.dart`
- Create: `apps/employee_app/lib/features/attachments/presentation/attachment_upload_page.dart`
- Create: `apps/employee_app/lib/features/attachments/presentation/employee_attachment_section.dart`
- Modify: `apps/employee_app/lib/features/employees/presentation/employee_detail_page.dart`
- Modify: `apps/employee_app/lib/app/router/app_router.dart`
- Test: `apps/employee_app/test/features/attachments/attachment_controller_test.dart`
- Test: `apps/employee_app/test/features/attachments/attachment_page_test.dart`
- Modify: `apps/employee_app/test/features/employees/employee_detail_page_test.dart`
- Modify: `apps/employee_app/test/app/router/app_router_test.dart`

**Interfaces:**

- Produces: family `attachmentControllerProvider(employeeId)` with list/retry/delete/download.
- Produces: family `attachmentUploadControllerProvider(employeeId)` with chooseFile/submit and duplicate-submit protection.
- Produces routes `/employees/:id/attachments` and `/employees/:id/attachments/upload`.

- [x] **Step 1: Write failing controller tests**

```dart
test('upload controller blocks duplicate submit and refreshes attachment list', () async {
  final first = controller.submit();
  final second = controller.submit();
  await expectLater(second, throwsStateError);
  await first;
  expect(container.read(attachmentControllerProvider(employeeId)).value?.items, hasLength(1));
});
```

Cover loading, empty, retry after Failure, successful delete, download cancellation, picker cancellation, invalid local type/size and server upload error.

- [x] **Step 2: Write failing widget/router tests**

```dart
testWidgets('employee attachment page shows safe metadata and manager actions', (tester) async {
  await tester.pumpWidget(managerHarness());
  await tester.pumpAndSettle();
  expect(find.text('员工附件'), findsOneWidget);
  expect(find.text('合同.pdf'), findsOneWidget);
  expect(find.text('1.0 KB'), findsOneWidget);
  expect(find.text('上传附件'), findsOneWidget);
  expect(find.text('删除'), findsOneWidget);
});
```

Also assert employee self sees list/download but no upload/delete, employee viewing another profile sees no attachment section, and HR/system route is allowed by existing capability while backend still decides authorization.

- [x] **Step 3: Verify RED**

Run: `flutter test test/features/attachments test/features/employees/employee_detail_page_test.dart test/app/router/app_router_test.dart`

Expected: compile/widget failure because controllers/pages/routes do not exist.

- [x] **Step 4: Implement immutable controller states**

```dart
class AttachmentState {
  const AttachmentState({
    required this.items,
    required this.count,
    required this.page,
    required this.hasNext,
    this.isLoadingMore = false,
    this.deletingIds = const {},
  });
  final List<EmployeeAttachment> items;
  final int count;
  final int page;
  final bool hasNext;
  final bool isLoadingMore;
  final Set<String> deletingIds;
}
```

Use AsyncNotifier family providers. `loadMore` fetches page 2+ and deterministically de-duplicates in server `-created_at, -id` order. Mutations must update state before/after requests in `try/finally`; upload/delete refresh through the prior loaded depth, preserving older loaded items and excluding the deleted ID. Platform picker/saver are injected providers, never called directly from Widgets.

- [x] **Step 5: Implement pages and detail section**

AttachmentPage provides loading/empty/error/retry/success, metadata, download and manager delete. Upload page shows selected name/size/type, disables submit while uploading and displays safe Failure messages. Employee detail includes `EmployeeAttachmentSection` only when current user employeeId equals target or `canManageEmployees` is true.

- [x] **Step 6: Verify GREEN**

Run the Step 3 command, then `flutter test` and the repository/platform tests from Task 6.

- [ ] **Step 7: Suggested commit boundary**

```text
feat: add flutter employee attachment management
```

## Task 8：文档、性能、双数据库与双平台验收

**Files:**

- Modify: `README.md`
- Modify: `docs/api-conventions.md`
- Create: `docs/file-storage-guide.md`
- Create: `docs/file-center-validation-report.md`
- Modify: `docs/security-baseline.md`
- Modify: `docs/plans/phase-six-file-center.md`
- Modify: `backend/tests/test_ci_contract.py` when check.ps1 storage inputs require a contract assertion

- [x] **Step 1: Document the implemented contract**

Record storage root/ownership/backup responsibilities, generated path format, allowed types, 10 MiB limit, soft-delete retention limitation, permission matrix, endpoints, stable errors and recovery from a missing physical file. Do not include real paths, credentials or employee files.

- [x] **Step 2: Run focused backend verification**

```powershell
Push-Location backend
.\.venv\Scripts\python.exe -m ruff format --check --no-cache .
.\.venv\Scripts\python.exe -m ruff check --no-cache .
.\.venv\Scripts\python.exe manage.py check --settings=config.settings.test
.\.venv\Scripts\python.exe manage.py makemigrations --check --dry-run --settings=config.settings.test
.\.venv\Scripts\python.exe -m pytest -q
Pop-Location
```

- [x] **Step 3: Run PostgreSQL and Strict OpenAPI**

Use the same complete read-only mounts and Redis test DB as `scripts/check.ps1`. Record exact passed/skipped counts. Generate OpenAPI with `--validate --fail-on-warn` and record zero warnings.

- [x] **Step 4: Run Flutter verification**

```powershell
Push-Location apps\employee_app
dart format --output=none --set-exit-if-changed .
flutter test
$env:TrackFileAccess = "false"
flutter build windows --debug --dart-define-from-file=..\..\config\dev.windows.json
$env:GRADLE_USER_HOME = [Environment]::GetEnvironmentVariable("GRADLE_USER_HOME", "User")
$env:PUB_CACHE = [Environment]::GetEnvironmentVariable("PUB_CACHE", "User")
flutter build apk --debug --dart-define-from-file=..\..\config\dev.android-emulator.json
Pop-Location
```

Run Flutter analyze through `scripts/flutter-analysis.ps1` to avoid the documented Chinese-path LSP issue.

- [x] **Step 5: Run final project gate**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1
```

Expected: Exit Code 0. Then run `git diff --check` and `scripts/repository-safety.ps1`; confirm `storage/`, uploaded files, `.env`, secrets, build output and caches are untracked/uncommitted.

- [ ] **Step 6: Suggested commit boundaries**

```text
docs: add file center design and storage guide
test: complete file center validation
```

## Plan Self-Review

- ADR-0009 model, storage, validation, permissions, API, audit, Flutter, performance and testing decisions map to Tasks 1-8.
- EmployeeAttachment, attachment action names, endpoint paths, stable error codes and Flutter repository/controller signatures are consistent across tasks.
- No task introduces a new Django app, dependency, authentication system, HR department scope, external storage or physical-delete workflow.
- `docs/environment-configuration.md` remains outside every file list.

## Final review fix wave (2026-08-21)

The final whole-branch review found six contract gaps. This single fix wave preserves Tasks 1-8 and follows one RED/GREEN cycle per finding:

- [x] Require `view_employeeattachment` before every non-superuser/system-admin read scope while preserving action-level 403 and object-level 404 semantics.
- [x] Retain attachment pagination metadata and make page 2+ reachable with deterministic de-duplication/order across refresh, upload, and delete.
- [x] Use a canonical file-type-specific download fallback and harmonize safe basename handling for internal `..`, Unicode, separators, and control characters.
- [x] Map HTTP 400 `attachment_storage_conflict` to the retry-specific simplified-Chinese failure.
- [x] Let an accepted Android document write finish across engine teardown, suppress its callback after disposal, and best-effort delete the created URI on write failure.
- [x] Create the production attachment root as UID/GID `10001`, mode `0700`, and verify copy-up ownership, writeability, and mode.

Final verification remains the complete Task 8 gate: focused RED/GREEN evidence, SQLite and PostgreSQL (including concurrency), strict OpenAPI, Flutter format/analyze/full tests, Windows and Android debug builds, `scripts/check.ps1`, `git diff --check`, and repository safety. Real slow-`DocumentsProvider` lifecycle validation remains a controlled-device warning unless a suitable device/provider is available; no dependency will be added for it.

Fresh final-fix evidence: focused backend 74 passed/1 SQLite PostgreSQL-only skip; focused Flutter 79 passed; dependency-free Kotlin lifecycle contract PASS; SQLite 276 passed/1 skip; PostgreSQL 273 passed/4 Windows-only skips plus concurrency 1 passed; Strict OpenAPI exit 0; Flutter 179 passed and analyze clean; Windows/Android Debug builds passed, with the Android build running the native contract; `scripts/check.ps1` exit 0. Final diff/safety evidence is recorded in the final-fix report.
