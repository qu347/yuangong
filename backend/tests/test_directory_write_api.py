from datetime import date

import pytest
from django.contrib.auth.models import Group
from django.core.management import call_command
from rest_framework.test import APIClient
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken
from rest_framework_simplejwt.tokens import RefreshToken

from modules.accounts.models import User
from modules.audit.models import AuditEvent
from modules.employees.models import Employee
from modules.organizations.models import Department, Position


@pytest.fixture
def management_users(db):
    call_command("sync_rbac", verbosity=0)
    users = {}
    for role in ("employee", "hr_admin", "system_admin"):
        user = User.objects.create_user(username=f"write_{role}")
        user.groups.add(Group.objects.get(name=role))
        users[role] = user
    return users


def client_for(user=None):
    client = APIClient()
    if user is not None:
        client.force_authenticate(user)
    return client


@pytest.mark.django_db
def test_department_create_enforces_role_matrix_and_records_audit(management_users):
    payload = {"code": "LEGAL", "name": "法务部", "sort_order": 50}

    assert client_for().post("/api/v1/departments/", payload, format="json").status_code == 401
    assert (
        client_for(management_users["employee"])
        .post("/api/v1/departments/", payload, format="json")
        .status_code
        == 403
    )
    created = client_for(management_users["hr_admin"]).post(
        "/api/v1/departments/", payload, format="json"
    )
    system_created = client_for(management_users["system_admin"]).post(
        "/api/v1/departments/",
        {"code": "RISK", "name": "风控部", "sort_order": 60},
        format="json",
    )

    assert created.status_code == 201
    assert created.json()["status"] == "active"
    assert system_created.status_code == 201
    assert list(AuditEvent.objects.values_list("action", "resource_type")) == [
        ("create", "department"),
        ("create", "department"),
    ]
    assert (
        client_for(management_users["hr_admin"])
        .delete(f"/api/v1/departments/{created.json()['id']}/")
        .status_code
        == 405
    )


@pytest.mark.django_db
def test_directory_uniqueness_conflicts_return_safe_409(management_users):
    Department.objects.create(code="DUPLICATE", name="已有部门")

    response = client_for(management_users["hr_admin"]).post(
        "/api/v1/departments/",
        {"code": "DUPLICATE", "name": "重复部门"},
        format="json",
    )

    assert response.status_code == 409
    assert response.json()["code"] == "uniqueness_conflict"
    assert "constraint" not in response.content.decode().lower()
    assert "organizations_department" not in response.content.decode().lower()


@pytest.mark.django_db
def test_department_create_rolls_back_when_audit_recording_fails(management_users, monkeypatch):
    from modules.organizations.services import create_department

    def fail_audit(**kwargs):
        del kwargs
        raise RuntimeError("injected audit failure")

    monkeypatch.setattr("modules.organizations.services.record_audit_event", fail_audit)

    with pytest.raises(RuntimeError, match="injected audit failure"):
        create_department(
            actor=management_users["hr_admin"],
            data={"code": "ROLLBACK", "name": "回滚部门"},
        )

    assert Department.objects.filter(code="ROLLBACK").exists() is False


@pytest.mark.django_db
def test_department_status_actions_are_idempotent_and_protect_active_dependencies(
    management_users,
):
    parent = Department.objects.create(code="PARENT", name="父部门")
    child = Department.objects.create(code="CHILD", name="子部门", parent=parent)
    hr_client = client_for(management_users["hr_admin"])

    blocked = hr_client.post(f"/api/v1/departments/{parent.id}/deactivate/", {}, format="json")
    first = hr_client.post(f"/api/v1/departments/{child.id}/deactivate/", {}, format="json")
    repeated = hr_client.post(f"/api/v1/departments/{child.id}/deactivate/", {}, format="json")
    parent_deactivated = hr_client.post(
        f"/api/v1/departments/{parent.id}/deactivate/", {}, format="json"
    )
    invalid_child = hr_client.post(
        "/api/v1/departments/",
        {"code": "INVALID-CHILD", "name": "无效子部门", "parent": str(parent.id)},
        format="json",
    )

    assert blocked.status_code == 409
    assert blocked.json()["code"] == "resource_in_use"
    assert blocked.json()["details"]["active_children"] == "1"
    assert first.status_code == 200
    assert first.json()["changed"] is True
    assert repeated.json()["changed"] is False
    assert parent_deactivated.status_code == 200
    assert invalid_child.status_code == 400


@pytest.mark.django_db
def test_position_writes_validate_department_and_active_employee_dependencies(management_users):
    active_department = Department.objects.create(code="ENG-W", name="研发写入部")
    inactive_department = Department.objects.create(
        code="OLD-W",
        name="停用部门",
        status=Department.Status.INACTIVE,
    )
    hr_client = client_for(management_users["hr_admin"])

    created = hr_client.post(
        "/api/v1/positions/",
        {
            "code": "ENG-W-SWE",
            "name": "写入工程师",
            "department": str(active_department.id),
        },
        format="json",
    )
    invalid = hr_client.post(
        "/api/v1/positions/",
        {
            "code": "OLD-W-SWE",
            "name": "无效岗位",
            "department": str(inactive_department.id),
        },
        format="json",
    )
    position = Position.objects.get(code="ENG-W-SWE")
    Employee.objects.create(
        employee_no="EMP-W-POS",
        full_name="岗位依赖员工",
        department=active_department,
        position=position,
    )
    blocked_deactivate = hr_client.post(
        f"/api/v1/positions/{position.id}/deactivate/", {}, format="json"
    )
    blocked_move = hr_client.patch(
        f"/api/v1/positions/{position.id}/",
        {"department": str(inactive_department.id)},
        format="json",
    )

    assert created.status_code == 201
    assert created.json()["department"]["id"] == str(active_department.id)
    assert invalid.status_code == 400
    assert blocked_deactivate.status_code == 409
    assert blocked_move.status_code == 409


@pytest.mark.django_db
def test_employee_create_patch_stale_check_and_relationship_validation(management_users):
    engineering = Department.objects.create(code="EMP-ENG", name="员工研发部")
    hr = Department.objects.create(code="EMP-HR", name="员工人力部")
    engineer = Position.objects.create(code="EMP-SWE", name="员工工程师", department=engineering)
    hr_client = client_for(management_users["hr_admin"])
    payload = {
        "employee_no": "EMP-W-1001",
        "full_name": "测试员工甲",
        "work_email": "employee.write@example.test",
        "work_phone": "010-5550-7001",
        "department": str(engineering.id),
        "position": str(engineer.id),
        "hire_date": "2026-08-17",
    }

    created = hr_client.post("/api/v1/employees/", payload, format="json")
    updated = hr_client.patch(
        f"/api/v1/employees/{created.json()['id']}/",
        {"full_name": "测试员工乙", "expected_updated_at": created.json()["updated_at"]},
        format="json",
    )
    stale = hr_client.patch(
        f"/api/v1/employees/{created.json()['id']}/",
        {"full_name": "不应覆盖", "expected_updated_at": created.json()["updated_at"]},
        format="json",
    )
    mismatch = hr_client.patch(
        f"/api/v1/employees/{created.json()['id']}/",
        {"department": str(hr.id), "expected_updated_at": updated.json()["updated_at"]},
        format="json",
    )

    assert created.status_code == 201
    assert updated.status_code == 200
    assert updated.json()["full_name"] == "测试员工乙"
    assert stale.status_code == 409
    assert stale.json()["code"] == "stale_object"
    assert mismatch.status_code == 400
    assert Employee.objects.get(pk=created.json()["id"]).full_name == "测试员工乙"


@pytest.mark.django_db
def test_depart_and_reactivate_are_idempotent_and_revoke_linked_users_sessions(management_users):
    department = Department.objects.create(code="LIFE", name="生命周期部")
    linked_user = User.objects.create_user(username="departing_user", password="test-only-9481")
    employee = Employee.objects.create(
        employee_no="EMP-LIFE-1",
        full_name="生命周期员工",
        department=department,
        user=linked_user,
        hire_date=date(2024, 1, 1),
    )
    RefreshToken.for_user(linked_user)
    RefreshToken.for_user(linked_user)
    hr_client = client_for(management_users["hr_admin"])

    departed = hr_client.post(f"/api/v1/employees/{employee.id}/depart/", {}, format="json")
    repeated = hr_client.post(f"/api/v1/employees/{employee.id}/depart/", {}, format="json")
    employee.refresh_from_db()
    linked_user.refresh_from_db()

    assert departed.status_code == 200
    assert departed.json()["changed"] is True
    assert repeated.json()["changed"] is False
    assert employee.employment_status == Employee.EmploymentStatus.DEPARTED
    assert linked_user.is_active is False
    assert BlacklistedToken.objects.filter(token__user=linked_user).count() == 2
    assert list(AuditEvent.objects.values_list("action", flat=True)) == [
        "account_deactivate",
        "depart",
    ]

    reactivated = hr_client.post(f"/api/v1/employees/{employee.id}/reactivate/", {}, format="json")
    repeated_reactivate = hr_client.post(
        f"/api/v1/employees/{employee.id}/reactivate/", {}, format="json"
    )
    linked_user.refresh_from_db()

    assert reactivated.status_code == 200
    assert reactivated.json()["changed"] is True
    assert reactivated.json()["account_requires_activation"] is True
    assert repeated_reactivate.json()["changed"] is False
    assert linked_user.is_active is False


@pytest.mark.django_db
def test_depart_rolls_back_employee_account_tokens_and_first_audit_when_second_audit_fails(
    management_users,
    monkeypatch,
):
    from modules.audit.services import record_audit_event as real_record_audit_event
    from modules.employees.services import depart_employee

    department = Department.objects.create(code="ROLLBACK-LIFE", name="回滚生命周期部")
    linked_user = User.objects.create_user(username="rollback_departing_user")
    employee = Employee.objects.create(
        employee_no="EMP-ROLLBACK-LIFE",
        full_name="回滚生命周期员工",
        department=department,
        user=linked_user,
    )
    RefreshToken.for_user(linked_user)
    calls = 0

    def fail_second_audit(**kwargs):
        nonlocal calls
        calls += 1
        if calls == 2:
            raise RuntimeError("injected second audit failure")
        return real_record_audit_event(**kwargs)

    monkeypatch.setattr("modules.employees.services.record_audit_event", fail_second_audit)

    with pytest.raises(RuntimeError, match="injected second audit failure"):
        depart_employee(employee_id=employee.id, actor=management_users["hr_admin"])

    employee.refresh_from_db()
    linked_user.refresh_from_db()
    assert employee.employment_status == Employee.EmploymentStatus.ACTIVE
    assert linked_user.is_active is True
    assert BlacklistedToken.objects.filter(token__user=linked_user).count() == 0
    assert AuditEvent.objects.count() == 0
