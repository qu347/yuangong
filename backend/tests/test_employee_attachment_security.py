from dataclasses import FrozenInstanceError
from io import BytesIO
from uuid import UUID
from zipfile import ZIP_DEFLATED, ZipFile

import pytest
from django.contrib.auth.models import Group
from django.core.exceptions import ValidationError
from django.core.files.storage import FileSystemStorage
from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.management import call_command
from rest_framework import status

from modules.accounts.models import User
from modules.audit.models import AuditEvent
from modules.employees.attachments.exceptions import (
    AttachmentFileMissing,
    AttachmentRequestError,
)
from modules.employees.attachments.storage import (
    attachment_storage_path,
    get_attachment_storage,
)
from modules.employees.attachments.validation import validate_attachment
from modules.employees.models import Employee, EmployeeAttachment
from modules.organizations.models import Department

PDF_BYTES = b"%PDF-1.7\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n"
JPEG_BYTES = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9"
PNG_BYTES = (
    b"\x89PNG\r\n\x1a\n"
    b"\x00\x00\x00\rIHDR"
    b"\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
    b"\x00\x00\x00\x00IEND\xaeB\x60\x82"
)
CONTENT_TYPES_XML = b"""<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>
"""


def make_ooxml_bytes(document_member, document_body=b"<document/>"):
    stream = BytesIO()
    with ZipFile(stream, "w", compression=ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", CONTENT_TYPES_XML)
        archive.writestr(document_member, document_body)
    return stream.getvalue()


DOCX_BYTES = make_ooxml_bytes("word/document.xml")
XLSX_BYTES = make_ooxml_bytes("xl/workbook.xml", b"<workbook/>")


@pytest.mark.parametrize(
    ("name", "content", "expected_name", "expected_type"),
    [
        ("合同.PdF", PDF_BYTES, "合同.PdF", "pdf"),
        ("照片.JPEG", JPEG_BYTES, "照片.JPEG", "jpg"),
        ("头像.jPg", JPEG_BYTES, "头像.jPg", "jpg"),
        ("截图.PnG", PNG_BYTES, "截图.PnG", "png"),
        ("说明.DoCx", DOCX_BYTES, "说明.DoCx", "docx"),
        ("报表.XlSx", XLSX_BYTES, "报表.XlSx", "xlsx"),
    ],
)
def test_attachment_validation_accepts_literal_signatures_and_normalizes_type(
    name,
    content,
    expected_name,
    expected_type,
):
    upload = SimpleUploadedFile(name, content)
    upload.seek(len(content))

    validated = validate_attachment(upload)

    assert validated.original_filename == expected_name
    assert validated.file_type == expected_type
    assert validated.file_size == len(content)
    assert upload.tell() == 0
    with pytest.raises(FrozenInstanceError):
        validated.file_size = 1


@pytest.mark.parametrize("name", ["run.exe", "script.js", "archive.zip", "app.apk"])
def test_attachment_validation_rejects_forbidden_extensions(name):
    upload = SimpleUploadedFile(name, b"forbidden")

    with pytest.raises(AttachmentRequestError) as error:
        validate_attachment(upload)

    assert error.value.error_code == "attachment_type_not_allowed"


def test_attachment_validation_rejects_double_extension_disguising_executable():
    upload = SimpleUploadedFile("合同.pdf.exe", PDF_BYTES)

    with pytest.raises(AttachmentRequestError) as error:
        validate_attachment(upload)

    assert error.value.error_code == "attachment_type_not_allowed"


def test_attachment_validation_rejects_zero_bytes_and_restores_stream():
    upload = SimpleUploadedFile("empty.pdf", b"")

    with pytest.raises(AttachmentRequestError) as error:
        validate_attachment(upload)

    assert error.value.error_code == "attachment_invalid_content"
    assert upload.tell() == 0


def test_attachment_validation_accepts_exact_ten_mibibytes():
    content = PDF_BYTES + b"\x00" * (10 * 1024 * 1024 - len(PDF_BYTES))
    upload = SimpleUploadedFile("limit.pdf", content)

    validated = validate_attachment(upload)

    assert validated.file_size == 10 * 1024 * 1024
    assert upload.tell() == 0


def test_attachment_validation_rejects_ten_mibibytes_plus_one_without_reading_content():
    content = PDF_BYTES + b"\x00" * (10 * 1024 * 1024 + 1 - len(PDF_BYTES))
    upload = SimpleUploadedFile("too-large.pdf", content)
    upload.seek(23)

    with pytest.raises(AttachmentRequestError) as error:
        validate_attachment(upload)

    assert error.value.error_code == "attachment_too_large"
    assert upload.tell() == 0


@pytest.mark.parametrize(
    ("name", "content"),
    [
        ("fake.pdf", PNG_BYTES),
        ("fake.jpg", PDF_BYTES),
        ("fake.png", JPEG_BYTES),
        ("fake.docx", XLSX_BYTES),
        ("fake.xlsx", DOCX_BYTES),
    ],
)
def test_attachment_validation_rejects_mismatched_content_signatures(name, content):
    upload = SimpleUploadedFile(name, content)

    with pytest.raises(AttachmentRequestError) as error:
        validate_attachment(upload)

    assert error.value.error_code == "attachment_invalid_content"
    assert upload.tell() == 0


@pytest.mark.parametrize("name", ["notes.docx", "data.xlsx"])
def test_attachment_validation_rejects_ordinary_zip(name):
    ordinary_zip = BytesIO()
    with ZipFile(ordinary_zip, "w", compression=ZIP_DEFLATED) as archive:
        archive.writestr("notes.txt", b"not an OOXML document")
    upload = SimpleUploadedFile(name, ordinary_zip.getvalue())

    with pytest.raises(AttachmentRequestError) as error:
        validate_attachment(upload)

    assert error.value.error_code == "attachment_invalid_content"
    assert upload.tell() == 0


def test_attachment_validation_sanitizes_client_path_controls_and_header_characters():
    upload = SimpleUploadedFile("placeholder.pdf", PDF_BYTES)
    upload._name = '../../folder\\合\r\n同";.pdf'

    validated = validate_attachment(upload)

    assert validated.original_filename == "合同.pdf"
    assert all(
        ord(character) >= 32 and ord(character) != 127 for character in validated.original_filename
    )
    assert not any(character in validated.original_filename for character in '\\";')
    assert "/" not in validated.original_filename


def test_attachment_validation_limits_sanitized_filename_to_model_capacity():
    upload = SimpleUploadedFile("placeholder.pdf", PDF_BYTES)
    upload._name = f"{'a' * 300}.pdf"

    validated = validate_attachment(upload)

    assert len(validated.original_filename) == 255
    assert validated.original_filename.endswith(".pdf")


def test_attachment_validation_accepts_internal_double_dot_unicode_basename():
    upload = SimpleUploadedFile("合同..😀.DOCX", DOCX_BYTES)

    validated = validate_attachment(upload)

    assert validated.original_filename == "合同..😀.DOCX"
    assert validated.file_type == "docx"


def test_attachment_path_uses_only_server_uuids_and_canonical_extension():
    employee_id = UUID("00000000-0000-0000-0000-000000000801")
    attachment_id = UUID("00000000-0000-0000-0000-000000000901")
    upload = SimpleUploadedFile("../../合同.pdf", PDF_BYTES)

    validated = validate_attachment(upload)
    path = attachment_storage_path(employee_id, attachment_id, validated.file_type)

    assert (
        path
        == "employee/00000000-0000-0000-0000-000000000801/00000000-0000-0000-0000-000000000901.pdf"
    )
    assert ".." not in path
    assert "合同" not in path
    assert "\\" not in path


@pytest.mark.parametrize(
    ("employee_id", "attachment_id", "file_type"),
    [
        ("../../outside", UUID("00000000-0000-0000-0000-000000000901"), "pdf"),
        (UUID("00000000-0000-0000-0000-000000000801"), "../../outside", "pdf"),
        (
            UUID("00000000-0000-0000-0000-000000000801"),
            UUID("00000000-0000-0000-0000-000000000901"),
            "../../pdf",
        ),
    ],
)
def test_attachment_path_rejects_non_server_identifiers(employee_id, attachment_id, file_type):
    with pytest.raises((TypeError, ValueError)):
        attachment_storage_path(employee_id, attachment_id, file_type)


def test_attachment_storage_uses_only_configured_private_root(settings):
    storage_root = settings.BASE_DIR / "test-private-attachments"
    settings.EMPLOYEE_ATTACHMENT_STORAGE_ROOT = storage_root

    storage = get_attachment_storage()

    assert isinstance(storage, FileSystemStorage)
    assert storage.base_location == storage_root
    assert storage.location == str(storage_root.resolve())


def test_attachment_file_missing_has_stable_not_found_contract():
    error = AttachmentFileMissing()

    assert error.status_code == status.HTTP_404_NOT_FOUND
    assert error.error_code == "attachment_file_missing"
    assert error.get_codes() == "attachment_file_missing"


@pytest.mark.django_db
def test_soft_delete_rolls_back_state_when_audit_write_fails(monkeypatch):
    from modules.employees.attachments.services import soft_delete_attachment

    call_command("sync_rbac", verbosity=0)
    department = Department.objects.create(code="ATT-TXN", name="附件事务部")
    actor = User.objects.create_user(username="attachment_delete_transaction")
    actor.groups.add(Group.objects.get(name="hr_admin"))
    employee = Employee.objects.create(
        employee_no="ATT-TXN-001",
        full_name="附件事务目标",
        department=department,
        hire_date="2024-02-01",
    )
    attachment = EmployeeAttachment.objects.create(
        employee=employee,
        filename="transaction.pdf",
        original_filename="事务.pdf",
        file_type=EmployeeAttachment.FileType.PDF,
        file_size=8,
        storage_path=f"employee/{employee.id}/transaction.pdf",
        uploaded_by=actor,
    )

    def reject_audit(**kwargs):
        del kwargs
        raise ValidationError("audit unavailable")

    monkeypatch.setattr(
        "modules.employees.attachments.services.record_audit_event",
        reject_audit,
    )

    with pytest.raises(ValidationError, match="audit unavailable"):
        soft_delete_attachment(attachment.id, actor)

    attachment.refresh_from_db()
    assert attachment.deleted_at is None
    assert not AuditEvent.objects.filter(resource_id=str(attachment.id)).exists()


@pytest.mark.django_db
def test_soft_delete_lock_query_rechecks_active_row_in_outer_predicate(monkeypatch):
    from modules.employees.attachments.services import soft_delete_attachment

    call_command("sync_rbac", verbosity=0)
    department = Department.objects.create(code="ATT-LOCK", name="附件锁定部")
    actor = User.objects.create_user(username="attachment_delete_lock")
    actor.groups.add(Group.objects.get(name="hr_admin"))
    employee = Employee.objects.create(
        employee_no="ATT-LOCK-001",
        full_name="附件锁定目标",
        department=department,
        hire_date="2024-02-01",
    )
    attachment = EmployeeAttachment.objects.create(
        employee=employee,
        filename="lock.pdf",
        original_filename="锁定.pdf",
        file_type=EmployeeAttachment.FileType.PDF,
        file_size=8,
        storage_path=f"employee/{employee.id}/lock.pdf",
        uploaded_by=actor,
    )
    filter_calls = []
    original_filter = EmployeeAttachment.objects.filter

    def capture_filter(*args, **kwargs):
        filter_calls.append(kwargs)
        return original_filter(*args, **kwargs)

    monkeypatch.setattr(EmployeeAttachment.objects, "filter", capture_filter)

    soft_delete_attachment(attachment.id, actor)

    assert any(call.get("deleted_at__isnull") is True and "pk__in" in call for call in filter_calls)
