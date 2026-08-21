from datetime import date
from uuid import UUID

import pytest
from django.contrib.auth.models import Group, Permission
from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.management import call_command
from django.http import Http404
from rest_framework.exceptions import PermissionDenied

from modules.accounts.models import User
from modules.audit.models import AuditEvent
from modules.employees.attachments.exceptions import AttachmentRequestError
from modules.employees.attachments.permissions import (
    get_visible_employee,
    visible_attachments,
)
from modules.employees.attachments.services import create_attachment
from modules.employees.attachments.storage import attachment_storage_path
from modules.employees.models import Employee, EmployeeAttachment
from modules.organizations.models import Department


@pytest.fixture
def attachment_scope(db):
    call_command("sync_rbac", verbosity=0)
    department = Department.objects.create(code="ATT-PERM", name="附件权限部")
    users = {}
    employees = {}
    for role in ("employee", "hr_admin", "system_admin"):
        user = User.objects.create_user(username=f"attachment_{role}")
        user.groups.add(Group.objects.get(name=role))
        employee = Employee.objects.create(
            employee_no=f"ATT-{role.upper()}",
            full_name=f"{role} 用户",
            department=department,
            user=user,
            hire_date=date(2024, 1, 1),
        )
        users[role] = user
        employees[role] = employee

    unlinked_employee = Employee.objects.create(
        employee_no="ATT-UNLINKED",
        full_name="无账号员工",
        department=department,
    )
    superuser = User.objects.create_superuser(username="attachment_superuser")
    superuser_employee = Employee.objects.create(
        employee_no="ATT-SUPERUSER",
        full_name="超级用户员工",
        department=department,
        user=superuser,
    )
    return {
        "department": department,
        "users": users,
        "employees": employees,
        "unlinked_employee": unlinked_employee,
        "superuser": superuser,
        "superuser_employee": superuser_employee,
    }


def make_attachment(*, employee, uploaded_by=None, suffix="001", deleted_at=None):
    attachment_id = UUID(f"00000000-0000-0000-0000-{int(suffix):012d}")
    return EmployeeAttachment.objects.create(
        id=attachment_id,
        employee=employee,
        filename=f"{attachment_id}.pdf",
        original_filename=f"附件-{suffix}.pdf",
        file_type=EmployeeAttachment.FileType.PDF,
        file_size=5,
        storage_path=f"employee/{employee.id}/{attachment_id}.pdf",
        uploaded_by=uploaded_by,
        deleted_at=deleted_at,
    )


@pytest.mark.django_db
def test_visible_attachments_limits_employee_to_own_active_rows(attachment_scope):
    employee_user = attachment_scope["users"]["employee"]
    own = make_attachment(employee=attachment_scope["employees"]["employee"], suffix="1")
    make_attachment(employee=attachment_scope["unlinked_employee"], suffix="2")

    visible_ids = list(visible_attachments(employee_user).values_list("id", flat=True))

    assert visible_ids == [own.id]


@pytest.mark.django_db
def test_employee_without_profile_has_no_visible_employee_or_attachments(attachment_scope):
    user = User.objects.create_user(username="attachment_no_profile")
    user.groups.add(Group.objects.get(name="employee"))

    assert visible_attachments(user).exists() is False
    with pytest.raises(Http404):
        get_visible_employee(
            user,
            attachment_scope["unlinked_employee"].id,
        )


@pytest.mark.django_db
def test_linked_user_without_view_permission_is_denied_before_read_scope(
    attachment_scope,
):
    user = User.objects.create_user(username="attachment_roleless_linked")
    employee = Employee.objects.create(
        employee_no="ATT-ROLELESS",
        full_name="无附件权限用户",
        department=attachment_scope["department"],
        user=user,
        hire_date=date(2024, 1, 1),
    )
    make_attachment(employee=employee, suffix="21")

    with pytest.raises(PermissionDenied):
        visible_attachments(user)
    with pytest.raises(PermissionDenied):
        get_visible_employee(user, employee.id)


@pytest.mark.django_db
@pytest.mark.parametrize(
    "permission_codename",
    ["add_employeeattachment", "change_employeeattachment"],
)
def test_attachment_write_permission_without_view_cannot_enter_read_scope(
    attachment_scope,
    permission_codename,
):
    user = User.objects.create_user(username=f"attachment_{permission_codename}_only")
    user.user_permissions.add(
        Permission.objects.get(
            content_type__app_label="employees",
            codename=permission_codename,
        )
    )

    with pytest.raises(PermissionDenied):
        visible_attachments(user)
    with pytest.raises(PermissionDenied):
        get_visible_employee(user, attachment_scope["unlinked_employee"].id)


@pytest.mark.django_db
def test_hr_scope_hides_system_admin_and_superuser_targets(attachment_scope):
    hr_user = attachment_scope["users"]["hr_admin"]
    ordinary = make_attachment(employee=attachment_scope["unlinked_employee"], suffix="3")
    make_attachment(employee=attachment_scope["employees"]["system_admin"], suffix="4")
    make_attachment(employee=attachment_scope["superuser_employee"], suffix="5")

    assert list(visible_attachments(hr_user).values_list("id", flat=True)) == [ordinary.id]
    assert get_visible_employee(hr_user, ordinary.employee_id, manage=True) == ordinary.employee
    with pytest.raises(Http404):
        get_visible_employee(
            hr_user,
            attachment_scope["employees"]["system_admin"].id,
            manage=True,
        )
    with pytest.raises(Http404):
        get_visible_employee(
            hr_user,
            attachment_scope["superuser_employee"].id,
            manage=True,
        )


@pytest.mark.django_db
def test_system_admin_scope_includes_all_targets(attachment_scope):
    system_user = attachment_scope["users"]["system_admin"]
    view_permission = Permission.objects.get(
        content_type__app_label="employees",
        codename="view_employeeattachment",
    )
    Group.objects.get(name="system_admin").permissions.remove(view_permission)
    attachments = [
        make_attachment(employee=attachment_scope["unlinked_employee"], suffix="6"),
        make_attachment(employee=attachment_scope["employees"]["system_admin"], suffix="7"),
        make_attachment(employee=attachment_scope["superuser_employee"], suffix="8"),
    ]

    assert set(visible_attachments(system_user).values_list("id", flat=True)) == {
        item.id for item in attachments
    }
    assert set(visible_attachments(attachment_scope["superuser"]).values_list("id", flat=True)) == {
        item.id for item in attachments
    }
    assert (
        get_visible_employee(
            system_user,
            attachment_scope["superuser_employee"].id,
            manage=True,
        )
        == attachment_scope["superuser_employee"]
    )


@pytest.mark.django_db
def test_employee_cannot_use_upload_service_for_own_employee(attachment_scope, settings, tmp_path):
    settings.EMPLOYEE_ATTACHMENT_STORAGE_ROOT = tmp_path
    user = attachment_scope["users"]["employee"]
    upload = SimpleUploadedFile("自助.pdf", b"%PDF-self-service")

    with pytest.raises(PermissionDenied):
        create_attachment(attachment_scope["employees"]["employee"], user, upload)

    assert list(tmp_path.rglob("*")) == []
    assert EmployeeAttachment.objects.count() == 0


@pytest.mark.django_db
def test_upload_service_rechecks_hr_target_instead_of_trusting_employee_object(
    attachment_scope,
    settings,
    tmp_path,
):
    settings.EMPLOYEE_ATTACHMENT_STORAGE_ROOT = tmp_path
    upload = SimpleUploadedFile("越权.pdf", b"%PDF-hidden-target")

    with pytest.raises(Http404):
        create_attachment(
            attachment_scope["employees"]["system_admin"],
            attachment_scope["users"]["hr_admin"],
            upload,
        )

    assert list(tmp_path.rglob("*")) == []
    assert EmployeeAttachment.objects.count() == 0


@pytest.mark.django_db
def test_upload_service_deletes_only_new_file_when_audit_fails(
    attachment_scope,
    settings,
    tmp_path,
    monkeypatch,
):
    settings.EMPLOYEE_ATTACHMENT_STORAGE_ROOT = tmp_path
    existing = tmp_path / "preserve.txt"
    existing.write_text("keep", encoding="utf-8")

    def fail_audit(**kwargs):
        del kwargs
        raise RuntimeError("injected attachment audit failure")

    monkeypatch.setattr(
        "modules.employees.attachments.services.record_audit_event",
        fail_audit,
    )
    upload = SimpleUploadedFile("合同.pdf", b"%PDF-audit-failure")

    with pytest.raises(RuntimeError, match="injected attachment audit failure"):
        create_attachment(
            attachment_scope["unlinked_employee"],
            attachment_scope["users"]["hr_admin"],
            upload,
        )

    assert existing.read_text(encoding="utf-8") == "keep"
    assert [path for path in tmp_path.rglob("*") if path.is_file()] == [existing]
    assert EmployeeAttachment.objects.count() == 0
    assert AuditEvent.objects.count() == 0


@pytest.mark.django_db
def test_upload_service_retries_storage_collision_with_new_canonical_uuid(
    attachment_scope,
    settings,
    tmp_path,
    monkeypatch,
):
    settings.EMPLOYEE_ATTACHMENT_STORAGE_ROOT = tmp_path
    employee = attachment_scope["unlinked_employee"]
    actor = attachment_scope["users"]["hr_admin"]
    colliding_id = UUID("00000000-0000-0000-0000-000000000991")
    replacement_id = UUID("00000000-0000-0000-0000-000000000992")
    colliding_path = attachment_storage_path(employee.id, colliding_id, "pdf")
    replacement_path = attachment_storage_path(employee.id, replacement_id, "pdf")
    existing_file = tmp_path / colliding_path
    existing_file.parent.mkdir(parents=True)
    existing_file.write_bytes(b"existing-canonical-file")
    generated_ids = iter((colliding_id, replacement_id))
    monkeypatch.setattr(
        "modules.employees.attachments.services.uuid.uuid4",
        lambda: next(generated_ids),
    )

    attachment = create_attachment(
        employee,
        actor,
        SimpleUploadedFile("碰撞.pdf", b"%PDF-new-upload"),
    )

    assert attachment.id == replacement_id
    assert attachment.filename == f"{replacement_id}.pdf"
    assert attachment.storage_path == replacement_path
    assert existing_file.read_bytes() == b"existing-canonical-file"
    assert (tmp_path / replacement_path).read_bytes() == b"%PDF-new-upload"
    assert {
        path.relative_to(tmp_path).as_posix() for path in tmp_path.rglob("*") if path.is_file()
    } == {colliding_path, replacement_path}
    assert list(EmployeeAttachment.objects.values_list("storage_path", flat=True)) == [
        replacement_path
    ]


@pytest.mark.django_db
def test_upload_service_stops_after_bounded_canonical_path_collisions(
    attachment_scope,
    settings,
    tmp_path,
    monkeypatch,
):
    settings.EMPLOYEE_ATTACHMENT_STORAGE_ROOT = tmp_path
    employee = attachment_scope["unlinked_employee"]
    collision_ids = [
        UUID(f"00000000-0000-0000-0000-{sequence:012d}") for sequence in (981, 982, 983)
    ]
    collision_paths = [
        attachment_storage_path(employee.id, attachment_id, "pdf")
        for attachment_id in collision_ids
    ]
    for collision_path in collision_paths:
        existing_file = tmp_path / collision_path
        existing_file.parent.mkdir(parents=True, exist_ok=True)
        existing_file.write_bytes(b"existing-canonical-file")
    generated_ids = iter(collision_ids)
    monkeypatch.setattr(
        "modules.employees.attachments.services.uuid.uuid4",
        lambda: next(generated_ids),
    )

    with pytest.raises(AttachmentRequestError) as error:
        create_attachment(
            employee,
            attachment_scope["users"]["hr_admin"],
            SimpleUploadedFile("连续碰撞.pdf", b"%PDF-bounded-collision"),
        )

    assert error.value.error_code == "attachment_storage_conflict"
    assert {
        path.relative_to(tmp_path).as_posix() for path in tmp_path.rglob("*") if path.is_file()
    } == set(collision_paths)
    assert EmployeeAttachment.objects.count() == 0
    assert AuditEvent.objects.count() == 0
