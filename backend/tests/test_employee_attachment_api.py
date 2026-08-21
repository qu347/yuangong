import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from uuid import UUID

import pytest
from django.conf import settings
from django.contrib.auth.models import Group, Permission
from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.management import call_command
from django.db import connection, connections
from django.test.utils import CaptureQueriesContext
from django.utils.dateparse import parse_datetime
from rest_framework.test import APIClient

from modules.accounts.models import User
from modules.audit.models import AuditEvent
from modules.employees.models import Employee, EmployeeAttachment
from modules.organizations.models import Department


@pytest.fixture
def attachment_api_scope(db, settings, tmp_path):
    settings.EMPLOYEE_ATTACHMENT_STORAGE_ROOT = tmp_path
    call_command("sync_rbac", verbosity=0)
    department = Department.objects.create(code="ATT-API", name="附件 API 部")
    users = {}
    employees = {}
    clients = {}
    for role in ("employee", "hr_admin", "system_admin"):
        user = User.objects.create_user(username=f"api_attachment_{role}")
        user.groups.add(Group.objects.get(name=role))
        employee = Employee.objects.create(
            employee_no=f"API-{role.upper()}",
            full_name=f"API {role}",
            department=department,
            user=user,
            hire_date=date(2024, 2, 1),
        )
        client = APIClient()
        client.force_authenticate(user)
        users[role] = user
        employees[role] = employee
        clients[role] = client

    target = Employee.objects.create(
        employee_no="API-TARGET",
        full_name="普通目标员工",
        department=department,
    )
    superuser = User.objects.create_superuser(username="api_attachment_superuser")
    superuser_target = Employee.objects.create(
        employee_no="API-SUPERUSER",
        full_name="超级用户目标",
        department=department,
        user=superuser,
    )
    return {
        "storage_root": tmp_path,
        "users": users,
        "employees": employees,
        "clients": clients,
        "target": target,
        "superuser_target": superuser_target,
    }


def create_attachment_row(*, employee, uploaded_by, sequence):
    attachment_id = UUID(f"10000000-0000-0000-0000-{sequence:012d}")
    return EmployeeAttachment.objects.create(
        id=attachment_id,
        employee=employee,
        filename=f"{attachment_id}.pdf",
        original_filename=f"资料-{sequence}.pdf",
        file_type=EmployeeAttachment.FileType.PDF,
        file_size=sequence,
        storage_path=f"employee/{employee.id}/{attachment_id}.pdf",
        uploaded_by=uploaded_by,
    )


def write_attachment_file(storage_root, attachment, content=b"%PDF-download"):
    path = storage_root / attachment.storage_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)
    return path


@pytest.mark.django_db
def test_attachment_list_and_upload_require_authentication(attachment_api_scope):
    url = f"/api/v1/employees/{attachment_api_scope['target'].id}/attachments/"

    assert APIClient().get(url).status_code == 401
    assert (
        APIClient()
        .post(url, {"file": SimpleUploadedFile("合同.pdf", b"%PDF-unauth")}, format="multipart")
        .status_code
        == 401
    )


@pytest.mark.django_db
def test_employee_lists_only_own_attachments(attachment_api_scope):
    own_employee = attachment_api_scope["employees"]["employee"]
    other_employee = attachment_api_scope["target"]
    uploader = attachment_api_scope["users"]["hr_admin"]
    own_attachment = create_attachment_row(employee=own_employee, uploaded_by=uploader, sequence=1)
    create_attachment_row(employee=other_employee, uploaded_by=uploader, sequence=2)
    client = attachment_api_scope["clients"]["employee"]

    response = client.get(f"/api/v1/employees/{own_employee.id}/attachments/")

    assert response.status_code == 200
    assert response.json()["count"] == 1
    payload = response.json()["results"][0]
    assert parse_datetime(payload.pop("created_at")) == own_attachment.created_at
    assert payload == {
        "id": str(own_attachment.id),
        "employee_id": str(own_employee.id),
        "filename": "资料-1.pdf",
        "file_type": "pdf",
        "file_size": 1,
        "uploaded_by": {"id": str(uploader.id), "username": uploader.username},
    }
    assert client.get(f"/api/v1/employees/{other_employee.id}/attachments/").status_code == 404


@pytest.mark.django_db
def test_employee_without_profile_cannot_list_employee_attachments(attachment_api_scope):
    user = User.objects.create_user(username="api_attachment_no_profile")
    user.groups.add(Group.objects.get(name="employee"))
    client = APIClient()
    client.force_authenticate(user)

    response = client.get(f"/api/v1/employees/{attachment_api_scope['target'].id}/attachments/")

    assert response.status_code == 404


@pytest.mark.django_db
def test_linked_roleless_user_cannot_list_or_download_own_attachment(
    attachment_api_scope,
):
    user = User.objects.create_user(username="api_attachment_roleless_linked")
    employee = Employee.objects.create(
        employee_no="API-ROLELESS",
        full_name="无附件权限用户",
        department=attachment_api_scope["target"].department,
        user=user,
        hire_date=date(2024, 2, 1),
    )
    attachment = create_attachment_row(
        employee=employee,
        uploaded_by=attachment_api_scope["users"]["hr_admin"],
        sequence=22,
    )
    write_attachment_file(attachment_api_scope["storage_root"], attachment)
    client = APIClient()
    client.force_authenticate(user)

    listed = client.get(f"/api/v1/employees/{employee.id}/attachments/")
    downloaded = client.get(f"/api/v1/attachments/{attachment.id}/download/")

    assert listed.status_code == 403
    assert downloaded.status_code == 403


@pytest.mark.django_db
@pytest.mark.parametrize(
    "permission_codename",
    ["add_employeeattachment", "change_employeeattachment"],
)
def test_attachment_write_permission_without_view_cannot_list_or_download(
    attachment_api_scope,
    permission_codename,
):
    user = User.objects.create_user(username=f"api_attachment_{permission_codename}_only")
    user.user_permissions.add(
        Permission.objects.get(
            content_type__app_label="employees",
            codename=permission_codename,
        )
    )
    attachment = create_attachment_row(
        employee=attachment_api_scope["target"],
        uploaded_by=attachment_api_scope["users"]["hr_admin"],
        sequence=23 if permission_codename.startswith("add") else 24,
    )
    write_attachment_file(attachment_api_scope["storage_root"], attachment)
    client = APIClient()
    client.force_authenticate(user)

    listed = client.get(f"/api/v1/employees/{attachment.employee_id}/attachments/")
    downloaded = client.get(f"/api/v1/attachments/{attachment.id}/download/")

    assert listed.status_code == 403
    assert downloaded.status_code == 403


@pytest.mark.django_db
def test_employee_upload_is_denied(attachment_api_scope):
    employee = attachment_api_scope["employees"]["employee"]
    response = attachment_api_scope["clients"]["employee"].post(
        f"/api/v1/employees/{employee.id}/attachments/",
        {"file": SimpleUploadedFile("自助.pdf", b"%PDF-self-upload")},
        format="multipart",
    )

    assert response.status_code == 403
    assert EmployeeAttachment.objects.count() == 0


@pytest.mark.django_db
def test_hr_upload_records_safe_metadata_file_and_audit(attachment_api_scope):
    employee = attachment_api_scope["target"]
    actor = attachment_api_scope["users"]["hr_admin"]
    response = attachment_api_scope["clients"]["hr_admin"].post(
        f"/api/v1/employees/{employee.id}/attachments/",
        {"file": SimpleUploadedFile("合同.pdf", b"%PDF-contract")},
        format="multipart",
        HTTP_X_REQUEST_ID="attachment-request-1",
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["filename"] == "合同.pdf"
    assert payload["employee_id"] == str(employee.id)
    assert payload["uploaded_by"] == {"id": str(actor.id), "username": actor.username}
    assert set(payload) == {
        "id",
        "employee_id",
        "filename",
        "file_type",
        "file_size",
        "uploaded_by",
        "created_at",
    }

    attachment = EmployeeAttachment.objects.get(pk=payload["id"])
    assert attachment.filename == f"{attachment.id}.pdf"
    assert attachment.storage_path == f"employee/{employee.id}/{attachment.id}.pdf"
    assert (
        attachment_api_scope["storage_root"] / attachment.storage_path
    ).read_bytes() == b"%PDF-contract"
    event = AuditEvent.objects.get(resource_id=payload["id"])
    assert event.action == "employee_attachment.create"
    assert event.actor == actor
    assert event.request_id == "attachment-request-1"
    assert event.changes == {
        "employee_no": {"to": employee.employee_no},
        "filename": {"to": "合同.pdf"},
        "file_type": {"to": "pdf"},
        "file_size": {"to": len(b"%PDF-contract")},
    }


@pytest.mark.django_db
def test_hr_cannot_list_or_upload_system_admin_target(attachment_api_scope):
    system_employee = attachment_api_scope["employees"]["system_admin"]
    url = f"/api/v1/employees/{system_employee.id}/attachments/"
    client = attachment_api_scope["clients"]["hr_admin"]

    assert client.get(url).status_code == 404
    assert (
        client.post(
            url,
            {"file": SimpleUploadedFile("隐藏.pdf", b"%PDF-hidden")},
            format="multipart",
        ).status_code
        == 404
    )
    assert client.post(url, {}, format="multipart").status_code == 404


@pytest.mark.django_db
def test_system_admin_can_list_and_upload_system_admin_target(attachment_api_scope):
    system_employee = attachment_api_scope["employees"]["system_admin"]
    client = attachment_api_scope["clients"]["system_admin"]
    url = f"/api/v1/employees/{system_employee.id}/attachments/"

    created = client.post(
        url,
        {"file": SimpleUploadedFile("系统.pdf", b"%PDF-system")},
        format="multipart",
    )
    listed = client.get(url)

    assert created.status_code == 201
    assert listed.status_code == 200
    assert listed.json()["results"][0]["id"] == created.json()["id"]


@pytest.mark.django_db
def test_upload_requires_multipart_file_field(attachment_api_scope):
    response = attachment_api_scope["clients"]["hr_admin"].post(
        f"/api/v1/employees/{attachment_api_scope['target'].id}/attachments/",
        {},
        format="multipart",
    )

    assert response.status_code == 400
    assert response.json()["code"] == "attachment_file_missing"


@pytest.mark.django_db
def test_employee_upload_permission_is_checked_before_missing_file_validation(
    attachment_api_scope,
):
    employee = attachment_api_scope["employees"]["employee"]

    response = attachment_api_scope["clients"]["employee"].post(
        f"/api/v1/employees/{employee.id}/attachments/",
        {},
        format="multipart",
    )

    assert response.status_code == 403


@pytest.mark.django_db
def test_upload_authorizes_action_and_target_before_invalid_file_field(
    attachment_api_scope,
):
    employee = attachment_api_scope["employees"]["employee"]
    employee_response = attachment_api_scope["clients"]["employee"].post(
        f"/api/v1/employees/{employee.id}/attachments/",
        {"file": "not-a-file"},
        format="multipart",
    )

    hr_client = attachment_api_scope["clients"]["hr_admin"]
    hidden_responses = [
        hr_client.post(
            f"/api/v1/employees/{target.id}/attachments/",
            {"file": "not-a-file"},
            format="multipart",
        )
        for target in (
            attachment_api_scope["employees"]["system_admin"],
            attachment_api_scope["superuser_target"],
        )
    ]

    assert employee_response.status_code == 403
    assert [response.status_code for response in hidden_responses] == [404, 404]


@pytest.mark.django_db
def test_attachment_list_query_count_is_constant_with_uploaded_by(attachment_api_scope):
    system_user = attachment_api_scope["users"]["system_admin"]
    system_user.is_superuser = True
    system_user.is_staff = True
    system_user.save(update_fields=["is_superuser", "is_staff"])
    employee = attachment_api_scope["target"]
    client = attachment_api_scope["clients"]["system_admin"]
    url = f"/api/v1/employees/{employee.id}/attachments/?page_size=100"
    create_attachment_row(employee=employee, uploaded_by=system_user, sequence=1)

    with CaptureQueriesContext(connection) as one_attachment_queries:
        one_response = client.get(url)

    for sequence in range(2, 21):
        create_attachment_row(employee=employee, uploaded_by=system_user, sequence=sequence)

    with CaptureQueriesContext(connection) as twenty_attachment_queries:
        twenty_response = client.get(url)

    assert one_response.status_code == 200
    assert twenty_response.status_code == 200
    assert twenty_response.json()["count"] == 20
    assert len(one_attachment_queries) == len(twenty_attachment_queries) == 3


@pytest.mark.django_db
def test_attachment_openapi_documents_multipart_input_and_safe_create_response():
    schema = (
        APIClient()
        .get(
            "/api/schema/",
            HTTP_ACCEPT="application/vnd.oai.openapi+json",
        )
        .json()
    )

    operation = schema["paths"]["/api/v1/employees/{employee_id}/attachments/"]["post"]
    multipart_schema = operation["requestBody"]["content"]["multipart/form-data"]["schema"]
    response_schema = operation["responses"]["201"]["content"]["application/json"]["schema"]

    assert multipart_schema == {
        "type": "object",
        "properties": {"file": {"type": "string", "format": "binary"}},
        "required": ["file"],
    }
    assert response_schema == {"$ref": "#/components/schemas/EmployeeAttachment"}


@pytest.mark.django_db
def test_download_streams_safe_file_without_exposing_path(attachment_api_scope):
    employee = attachment_api_scope["employees"]["employee"]
    attachment = create_attachment_row(
        employee=employee,
        uploaded_by=attachment_api_scope["users"]["hr_admin"],
        sequence=31,
    )
    write_attachment_file(attachment_api_scope["storage_root"], attachment)

    response = attachment_api_scope["clients"]["employee"].get(
        f"/api/v1/attachments/{attachment.id}/download/"
    )

    assert response.status_code == 200
    assert b"".join(response.streaming_content).startswith(b"%PDF-")
    assert response["Content-Type"] == "application/pdf"
    assert response["Content-Disposition"].endswith(".pdf")
    assert response["Cache-Control"] == "private, no-store"
    assert response["X-Content-Type-Options"] == "nosniff"
    assert str(settings.EMPLOYEE_ATTACHMENT_STORAGE_ROOT) not in str(response.headers)
    assert attachment.storage_path not in str(response.headers)


@pytest.mark.django_db
def test_download_hides_cross_user_deleted_and_nonexistent_attachments(
    attachment_api_scope,
):
    other_attachment = create_attachment_row(
        employee=attachment_api_scope["target"],
        uploaded_by=attachment_api_scope["users"]["hr_admin"],
        sequence=32,
    )
    own_attachment = create_attachment_row(
        employee=attachment_api_scope["employees"]["employee"],
        uploaded_by=attachment_api_scope["users"]["hr_admin"],
        sequence=33,
    )
    own_attachment.deleted_at = own_attachment.created_at
    own_attachment.save(update_fields=["deleted_at", "updated_at"])
    client = attachment_api_scope["clients"]["employee"]

    responses = [
        client.get(f"/api/v1/attachments/{other_attachment.id}/download/"),
        client.get(f"/api/v1/attachments/{own_attachment.id}/download/"),
        client.get("/api/v1/attachments/00000000-0000-0000-0000-000000000000/download/"),
    ]

    assert [response.status_code for response in responses] == [404, 404, 404]
    assert [response.json()["code"] for response in responses] == [
        "not_found",
        "not_found",
        "not_found",
    ]


@pytest.mark.django_db
def test_download_reports_missing_physical_file_without_exposing_path(
    attachment_api_scope,
):
    employee = attachment_api_scope["employees"]["employee"]
    attachment = create_attachment_row(
        employee=employee,
        uploaded_by=attachment_api_scope["users"]["hr_admin"],
        sequence=34,
    )

    response = attachment_api_scope["clients"]["employee"].get(
        f"/api/v1/attachments/{attachment.id}/download/"
    )

    assert response.status_code == 404
    assert response.json()["code"] == "attachment_file_missing"
    assert attachment.storage_path not in str(response.json())
    assert str(attachment_api_scope["storage_root"]) not in str(response.json())


@pytest.mark.django_db
def test_download_content_disposition_does_not_emit_filename_control_characters(
    attachment_api_scope,
):
    employee = attachment_api_scope["employees"]["employee"]
    attachment = create_attachment_row(
        employee=employee,
        uploaded_by=attachment_api_scope["users"]["hr_admin"],
        sequence=35,
    )
    EmployeeAttachment.objects.filter(pk=attachment.pk).update(
        original_filename='合同\r\nX-Injected: yes";.pdf'
    )
    attachment.refresh_from_db()
    write_attachment_file(attachment_api_scope["storage_root"], attachment)

    response = attachment_api_scope["clients"]["employee"].get(
        f"/api/v1/attachments/{attachment.id}/download/"
    )

    assert response.status_code == 200
    disposition = response["Content-Disposition"]
    assert "\r" not in disposition
    assert "\n" not in disposition
    assert "X-Injected:" not in disposition


@pytest.mark.django_db
def test_delete_soft_deletes_and_keeps_file(attachment_api_scope):
    employee = attachment_api_scope["target"]
    actor = attachment_api_scope["users"]["hr_admin"]
    attachment = create_attachment_row(employee=employee, uploaded_by=actor, sequence=36)
    physical_path = write_attachment_file(attachment_api_scope["storage_root"], attachment)

    response = attachment_api_scope["clients"]["hr_admin"].delete(
        f"/api/v1/attachments/{attachment.id}/",
        HTTP_X_REQUEST_ID="attachment-delete-1",
    )

    attachment.refresh_from_db()
    assert response.status_code == 204
    assert response.content == b""
    assert attachment.deleted_at is not None
    assert physical_path.exists()
    event = AuditEvent.objects.get(resource_id=str(attachment.id))
    assert event.action == "employee_attachment.delete"
    assert event.actor == actor
    assert event.request_id == "attachment-delete-1"


@pytest.mark.django_db
def test_employee_delete_is_denied_before_attachment_lookup(attachment_api_scope):
    client = attachment_api_scope["clients"]["employee"]

    missing = client.delete("/api/v1/attachments/00000000-0000-0000-0000-000000000000/")

    assert missing.status_code == 403


@pytest.mark.django_db
def test_hr_delete_hides_system_admin_target(attachment_api_scope):
    attachment = create_attachment_row(
        employee=attachment_api_scope["employees"]["system_admin"],
        uploaded_by=attachment_api_scope["users"]["system_admin"],
        sequence=37,
    )

    response = attachment_api_scope["clients"]["hr_admin"].delete(
        f"/api/v1/attachments/{attachment.id}/"
    )

    attachment.refresh_from_db()
    assert response.status_code == 404
    assert response.json()["code"] == "not_found"
    assert attachment.deleted_at is None


@pytest.mark.django_db
def test_system_admin_can_delete_system_admin_target(attachment_api_scope):
    actor = attachment_api_scope["users"]["system_admin"]
    attachment = create_attachment_row(
        employee=attachment_api_scope["employees"]["system_admin"],
        uploaded_by=actor,
        sequence=38,
    )

    response = attachment_api_scope["clients"]["system_admin"].delete(
        f"/api/v1/attachments/{attachment.id}/"
    )

    attachment.refresh_from_db()
    assert response.status_code == 204
    assert attachment.deleted_at is not None


@pytest.mark.django_db
def test_deleted_and_nonexistent_attachments_are_hidden_from_repeat_delete(
    attachment_api_scope,
):
    actor = attachment_api_scope["users"]["hr_admin"]
    attachment = create_attachment_row(
        employee=attachment_api_scope["target"],
        uploaded_by=actor,
        sequence=39,
    )
    client = attachment_api_scope["clients"]["hr_admin"]
    first = client.delete(f"/api/v1/attachments/{attachment.id}/")

    responses = [
        client.delete(f"/api/v1/attachments/{attachment.id}/"),
        client.delete("/api/v1/attachments/00000000-0000-0000-0000-000000000000/"),
    ]

    assert first.status_code == 204
    assert [response.status_code for response in responses] == [404, 404]


@pytest.mark.django_db
def test_long_safe_filename_upload_and_delete_commit_bounded_audit_labels(
    attachment_api_scope,
):
    long_filename = f"{'a' * 251}.pdf"
    employee = attachment_api_scope["target"]
    client = attachment_api_scope["clients"]["hr_admin"]

    created = client.post(
        f"/api/v1/employees/{employee.id}/attachments/",
        {"file": SimpleUploadedFile(long_filename, b"%PDF-long-name")},
        format="multipart",
    )

    assert created.status_code == 201
    assert created.json()["filename"] == long_filename
    attachment_id = created.json()["id"]
    create_event = AuditEvent.objects.get(
        action="employee_attachment.create",
        resource_id=attachment_id,
    )
    assert create_event.resource_label == long_filename[:200]
    assert len(create_event.resource_label) == 200
    assert create_event.changes["filename"] == {"to": long_filename}

    deleted = client.delete(f"/api/v1/attachments/{attachment_id}/")

    assert deleted.status_code == 204
    attachment = EmployeeAttachment.objects.get(pk=attachment_id)
    assert attachment.deleted_at is not None
    delete_event = AuditEvent.objects.get(
        action="employee_attachment.delete",
        resource_id=attachment_id,
    )
    assert delete_event.resource_label == long_filename[:200]
    assert len(delete_event.resource_label) == 200
    assert delete_event.changes["filename"] == {"from": long_filename}


@pytest.mark.django_db(transaction=True)
def test_concurrent_attachment_delete_has_one_success_and_one_hidden_not_found(
    attachment_api_scope,
    monkeypatch,
):
    if connection.vendor != "postgresql":
        pytest.skip("PostgreSQL row-lock concurrency contract")

    employee = attachment_api_scope["target"]
    actor_id = attachment_api_scope["users"]["hr_admin"].id
    attachment = create_attachment_row(
        employee=employee,
        uploaded_by=attachment_api_scope["users"]["hr_admin"],
        sequence=40,
    )
    barrier = threading.Barrier(2)
    from modules.employees.attachments import services as attachment_services

    original_record_audit_event = attachment_services.record_audit_event

    def slow_record_audit_event(**kwargs):
        time.sleep(0.5)
        return original_record_audit_event(**kwargs)

    monkeypatch.setattr(
        attachment_services,
        "record_audit_event",
        slow_record_audit_event,
    )

    def delete_together():
        try:
            actor = User.objects.get(pk=actor_id)
            client = APIClient()
            client.force_authenticate(actor)
            barrier.wait(timeout=5)
            return client.delete(f"/api/v1/attachments/{attachment.id}/").status_code
        finally:
            connections.close_all()

    with ThreadPoolExecutor(max_workers=2) as executor:
        statuses = list(executor.map(lambda _: delete_together(), range(2)))

    assert sorted(statuses) == [204, 404]
    attachment.refresh_from_db()
    assert attachment.deleted_at is not None
    assert (
        AuditEvent.objects.filter(
            action="employee_attachment.delete",
            resource_id=str(attachment.id),
        ).count()
        == 1
    )
