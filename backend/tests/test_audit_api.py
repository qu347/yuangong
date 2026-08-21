import pytest
from django.contrib.auth.models import Group
from django.core.exceptions import ValidationError
from django.core.management import call_command
from rest_framework.test import APIClient

from modules.accounts.models import User
from modules.audit.models import AuditEvent


@pytest.mark.django_db
def test_audit_recorder_accepts_safe_changes_and_rejects_sensitive_keys():
    from modules.audit.services import record_audit_event

    actor = User.objects.create_user(username="audit_recorder")
    event = record_audit_event(
        actor=actor,
        action="update",
        resource_type="employee",
        resource_id="EMP-0001",
        resource_label="虚构员工",
        changes={"full_name": {"from": "旧名称", "to": "新名称"}},
        source="api",
    )

    assert event.actor == actor
    assert event.changes == {"full_name": {"from": "旧名称", "to": "新名称"}}
    with pytest.raises(ValidationError, match="敏感"):
        record_audit_event(
            actor=actor,
            action="update",
            resource_type="employee",
            resource_id="EMP-0001",
            resource_label="虚构员工",
            changes={"token": {"to": "must-not-be-stored"}},
            source="api",
        )
    assert AuditEvent.objects.count() == 1


@pytest.mark.django_db
def test_attachment_audit_actions_and_safe_metadata_are_supported():
    from modules.audit.services import record_audit_event

    actor = User.objects.create_user(username="attachment_auditor")
    event = record_audit_event(
        actor=actor,
        action=AuditEvent.Action.EMPLOYEE_ATTACHMENT_CREATE,
        resource_type="employee_attachment",
        resource_id="00000000-0000-0000-0000-000000000901",
        resource_label="合同.pdf",
        changes={
            "filename": {"to": "合同.pdf"},
            "file_type": {"to": "pdf"},
            "file_size": {"to": 1024},
        },
        source=AuditEvent.Source.API,
    )

    assert AuditEvent.Action.EMPLOYEE_ATTACHMENT_CREATE == "employee_attachment.create"
    assert AuditEvent.Action.EMPLOYEE_ATTACHMENT_DELETE == "employee_attachment.delete"
    assert event.action == "employee_attachment.create"


@pytest.mark.django_db
def test_audit_api_requires_view_permission_and_is_read_only():
    call_command("sync_rbac", verbosity=0)
    employee_user = User.objects.create_user(username="audit_employee")
    employee_user.groups.add(Group.objects.get(name="employee"))
    hr_user = User.objects.create_user(username="audit_hr")
    hr_user.groups.add(Group.objects.get(name="hr_admin"))
    event = AuditEvent.objects.create(
        actor=hr_user,
        action="update",
        resource_type="department",
        resource_id="DEP-1",
        resource_label="虚构部门",
        changes={"name": {"from": "旧", "to": "新"}},
        source="api",
    )
    client = APIClient()

    assert client.get("/api/v1/audit-events/").status_code == 401
    client.force_authenticate(employee_user)
    assert client.get("/api/v1/audit-events/").status_code == 403
    client.force_authenticate(hr_user)
    listed = client.get("/api/v1/audit-events/")
    detailed = client.get(f"/api/v1/audit-events/{event.id}/")

    assert listed.status_code == 200
    assert listed.json()["count"] == 1
    assert listed.json()["results"][0]["resource_label"] == "虚构部门"
    assert detailed.status_code == 200
    assert detailed.json()["id"] == str(event.id)
    assert client.post("/api/v1/audit-events/", {}, format="json").status_code == 405
    assert client.patch(f"/api/v1/audit-events/{event.id}/", {}, format="json").status_code == 405
    assert client.delete(f"/api/v1/audit-events/{event.id}/").status_code == 405


@pytest.mark.django_db
def test_audit_api_filters_and_paginates_in_reverse_created_order():
    call_command("sync_rbac", verbosity=0)
    hr_user = User.objects.create_user(username="audit_filter_hr")
    hr_user.groups.add(Group.objects.get(name="hr_admin"))
    first = AuditEvent.objects.create(
        actor=hr_user,
        action="create",
        resource_type="employee",
        resource_id="EMP-1001",
        resource_label="第一名虚构员工",
        changes={"employee_no": {"to": "EMP-1001"}},
        source="api",
    )
    second = AuditEvent.objects.create(
        actor=hr_user,
        action="update",
        resource_type="employee",
        resource_id="EMP-1002",
        resource_label="第二名虚构员工",
        changes={"full_name": {"from": "旧", "to": "新"}},
        source="admin",
    )
    client = APIClient()
    client.force_authenticate(hr_user)

    response = client.get(
        "/api/v1/audit-events/",
        {"action": "update", "resource_type": "employee", "page_size": 1},
    )

    assert response.status_code == 200
    assert response.json()["count"] == 1
    assert response.json()["results"][0]["id"] == str(second.id)
    assert response.json()["results"][0]["id"] != str(first.id)
