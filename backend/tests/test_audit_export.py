import csv
import io
import json

import pytest
from django.contrib.auth.models import Group
from django.core.management import call_command
from django.test import override_settings
from rest_framework.test import APIClient

from modules.accounts.models import User
from modules.audit.models import AuditEvent

EXPORT_URL = "/api/v1/audit-events/export.csv"


def client_for(user=None):
    client = APIClient()
    if user is not None:
        client.force_authenticate(user)
    return client


@pytest.fixture
def audit_export_users(db):
    call_command("sync_rbac", verbosity=0)
    users = {}
    for role in ("employee", "hr_admin", "system_admin"):
        user = User.objects.create_user(username=f"export_{role}")
        user.groups.add(Group.objects.get(name=role))
        users[role] = user
    return users


@pytest.mark.django_db
def test_audit_export_is_system_admin_only(audit_export_users):
    assert client_for().get(EXPORT_URL).status_code == 401
    assert client_for(audit_export_users["employee"]).get(EXPORT_URL).status_code == 403
    assert client_for(audit_export_users["hr_admin"]).get(EXPORT_URL).status_code == 403

    response = client_for(audit_export_users["system_admin"]).get(EXPORT_URL)

    assert response.status_code == 200
    assert response["Content-Type"].startswith("text/csv")


@pytest.mark.django_db
def test_audit_export_uses_fixed_utf8_csv_and_neutralizes_formulas(audit_export_users):
    actor = audit_export_users["system_admin"]
    selected = AuditEvent.objects.create(
        actor=actor,
        action="update",
        resource_type="employee",
        resource_id="+EMP-1001",
        resource_label='=SUM(1,2),"虚构员工"\n下一行',
        changes={"z": {"to": "末尾"}, "a": {"from": "旧", "to": "新"}},
        source="api",
        request_id="\trequest-safe",
    )
    AuditEvent.objects.create(
        actor=None,
        action="create",
        resource_type="department",
        resource_id="DEP-2",
        resource_label="@虚构部门",
        changes={},
        source="system",
        request_id=None,
    )

    response = client_for(actor).get(
        EXPORT_URL,
        {"action": "update", "resource_type": "employee", "ordering": "created_at"},
    )

    assert response.status_code == 200
    assert response.content.startswith(b"\xef\xbb\xbf")
    rows = list(csv.DictReader(io.StringIO(response.content.decode("utf-8-sig"), newline="")))
    assert len(rows) == 1
    assert rows[0]["resource_id"] == "'+EMP-1001"
    assert rows[0]["resource_label"] == '\'=SUM(1,2),"虚构员工"\n下一行'
    assert rows[0]["request_id"] == "'\trequest-safe"
    assert rows[0]["actor_username"] == actor.username
    assert rows[0]["changes"] == json.dumps(
        selected.changes,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    exported = AuditEvent.objects.get(action="audit_exported")
    assert exported.actor == actor
    assert exported.changes == {
        "filters": {
            "action": "update",
            "ordering": "created_at",
            "resource_type": "employee",
        },
        "format": "csv",
        "row_count": 1,
    }
    assert str(exported.id) not in response.content.decode("utf-8-sig")


@pytest.mark.django_db
def test_audit_export_represents_deleted_actor_as_empty(audit_export_users):
    event = AuditEvent.objects.create(
        actor=None,
        action="create",
        resource_type="department",
        resource_id="DEP-NULL",
        resource_label="虚构部门",
        changes={},
        source="system",
    )

    response = client_for(audit_export_users["system_admin"]).get(
        EXPORT_URL,
        {"resource_id": event.resource_id},
    )

    rows = list(csv.DictReader(io.StringIO(response.content.decode("utf-8-sig"))))
    assert rows[0]["actor_username"] == ""


@pytest.mark.django_db
@override_settings(AUDIT_EXPORT_MAX_ROWS=1)
def test_audit_export_rejects_oversized_result_without_success_audit(audit_export_users):
    actor = audit_export_users["system_admin"]
    for number in (1, 2):
        AuditEvent.objects.create(
            actor=actor,
            action="update",
            resource_type="employee",
            resource_id=f"EMP-{number}",
            resource_label=f"虚构员工{number}",
            changes={},
            source="api",
        )

    response = client_for(actor).get(EXPORT_URL)

    assert response.status_code == 400
    assert response.json()["code"] == "export_too_large"
    assert response.json()["details"] == {"count": 2, "limit": 1}
    assert not AuditEvent.objects.filter(action="audit_exported").exists()
