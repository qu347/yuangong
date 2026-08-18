import json
import threading
from concurrent.futures import ThreadPoolExecutor

import pytest
from django.contrib.auth.models import Group
from django.core import mail
from django.core.management import call_command
from django.db import connection, connections
from rest_framework.test import APIClient

from modules.accounts.models import AccountSession, User
from modules.audit.models import AuditEvent
from modules.employees.models import Employee
from modules.organizations.models import Department

INITIAL_PASSWORD = "Aster!River7Cobalt"
RESET_PASSWORD = "Quartz!Forest7Harbor"


def _one_time_code_from_latest_message():
    return mail.outbox[-1].body.split("一次性代码：", 1)[1].splitlines()[0].strip()


def _login(identifier, password, platform):
    return APIClient().post(
        "/api/v1/auth/login/",
        {
            "identifier": identifier,
            "password": password,
            "client_platform": platform,
            "client_name": f"{platform.title()} integration",
            "app_version": "0.1.0-test",
        },
        format="json",
    )


def _authenticated_client(access):
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    return client


@pytest.mark.django_db
def test_complete_invitation_session_reset_and_account_lifecycle_flow():
    call_command("sync_rbac", verbosity=0)
    department = Department.objects.create(code="E2E", name="安全闭环验证部")
    employee = Employee.objects.create(
        employee_no="E2E-0001",
        full_name="虚构安全闭环员工",
        work_email="security.flow@example.invalid",
        department=department,
    )
    admin = User.objects.create_user(
        username="security_flow_admin",
        email="security.flow.admin@example.invalid",
        password=INITIAL_PASSWORD,
    )
    admin.groups.add(Group.objects.get(name="system_admin"))
    admin_login = _login(admin.username, INITIAL_PASSWORD, "windows")
    assert admin_login.status_code == 200
    admin_client = _authenticated_client(admin_login.json()["access"])

    invitation_response = admin_client.post(
        "/api/v1/accounts/invitations/",
        {
            "employee_id": str(employee.id),
            "username": "security.flow.employee",
            "email": employee.work_email,
            "target_role": "employee",
        },
        format="json",
    )
    assert invitation_response.status_code == 201
    invitation_payload = invitation_response.json()
    assert not {"token", "token_digest", "password"} & set(invitation_payload)
    invitation_id = invitation_payload["id"]
    invitation_list = admin_client.get("/api/v1/accounts/invitations/")
    assert invitation_list.status_code == 200
    assert invitation_list.json()[0]["id"] == invitation_id

    invitation_code = _one_time_code_from_latest_message()
    invitation_accept = APIClient().post(
        "/api/v1/auth/invitations/accept/",
        {"token": invitation_code, "new_password": INITIAL_PASSWORD},
        format="json",
    )
    invitation_replay = APIClient().post(
        "/api/v1/auth/invitations/accept/",
        {"token": invitation_code, "new_password": INITIAL_PASSWORD},
        format="json",
    )
    assert invitation_accept.status_code == 204
    assert invitation_replay.status_code == 400

    employee.refresh_from_db()
    account = employee.user
    assert account is not None
    windows_login = _login(account.email.upper(), INITIAL_PASSWORD, "windows")
    android_login = _login(account.username, INITIAL_PASSWORD, "android")
    assert windows_login.status_code == android_login.status_code == 200
    windows_tokens = windows_login.json()
    android_tokens = android_login.json()
    windows_client = _authenticated_client(windows_tokens["access"])

    session_response = windows_client.get("/api/v1/auth/sessions/")
    assert session_response.status_code == 200
    sessions = session_response.json()
    assert len(sessions) == 2
    assert sum(item["is_current"] for item in sessions) == 1
    assert all("jti" not in json.dumps(item).lower() for item in sessions)
    android_session_id = next(item["id"] for item in sessions if not item["is_current"])
    revoked = windows_client.post(
        f"/api/v1/auth/sessions/{android_session_id}/revoke/", {}, format="json"
    )
    assert revoked.status_code == 200
    assert _authenticated_client(android_tokens["access"]).get("/api/v1/me/").status_code == 401
    assert (
        APIClient()
        .post(
            "/api/v1/auth/refresh/",
            {"refresh": android_tokens["refresh"]},
            format="json",
        )
        .status_code
        == 401
    )

    reset_request = APIClient().post(
        "/api/v1/auth/password-reset/request/",
        {"identifier": account.email},
        format="json",
    )
    assert reset_request.status_code == 202
    reset_code = _one_time_code_from_latest_message()
    reset_confirm = APIClient().post(
        "/api/v1/auth/password-reset/confirm/",
        {"token": reset_code, "new_password": RESET_PASSWORD},
        format="json",
    )
    reset_replay = APIClient().post(
        "/api/v1/auth/password-reset/confirm/",
        {"token": reset_code, "new_password": RESET_PASSWORD},
        format="json",
    )
    assert reset_confirm.status_code == 204
    assert reset_replay.status_code == 400
    assert _login(account.username, INITIAL_PASSWORD, "windows").status_code == 401
    assert windows_client.get("/api/v1/me/").status_code == 401

    reset_login = _login(account.username, RESET_PASSWORD, "windows")
    assert reset_login.status_code == 200
    reset_client = _authenticated_client(reset_login.json()["access"])
    deactivated = admin_client.post(f"/api/v1/accounts/{account.id}/deactivate/", {}, format="json")
    assert deactivated.status_code == 200
    assert reset_client.get("/api/v1/me/").status_code == 401
    employee.refresh_from_db()
    assert employee.employment_status == Employee.EmploymentStatus.ACTIVE
    assert _login(account.username, RESET_PASSWORD, "android").status_code == 401

    activated = admin_client.post(f"/api/v1/accounts/{account.id}/activate/", {}, format="json")
    assert activated.status_code == 200
    assert reset_client.get("/api/v1/me/").status_code == 401
    reactivated_login = _login(account.username, RESET_PASSWORD, "android")
    assert reactivated_login.status_code == 200
    changed_role = admin_client.post(
        f"/api/v1/accounts/{account.id}/change-role/",
        {"role": "hr_admin"},
        format="json",
    )
    assert changed_role.status_code == 200
    assert changed_role.json()["role"] == "hr_admin"
    assert (
        _authenticated_client(reactivated_login.json()["access"]).get("/api/v1/me/").status_code
        == 401
    )

    actions = set(
        AuditEvent.objects.filter(
            resource_id__in=[str(account.id), str(invitation_id)]
        ).values_list("action", flat=True)
    )
    assert {
        "account_invitation_created",
        "account_invitation_accepted",
        "password_reset_completed",
        "account_deactivate",
        "account_activated",
        "account_role_changed",
    } <= actions
    for changes in AuditEvent.objects.values_list("changes", flat=True):
        serialized = json.dumps(changes).casefold()
        assert all(
            fragment not in serialized
            for fragment in ("password", "token", "jti", "authorization", "邮件正文")
        )
    assert not AccountSession.objects.filter(user=account, revoked_at=None).exists()


@pytest.mark.django_db(transaction=True)
def test_concurrent_invitation_acceptance_creates_only_one_account():
    call_command("sync_rbac", verbosity=0)
    department = Department.objects.create(code="RACE", name="邀请并发验证部")
    employee = Employee.objects.create(
        employee_no="RACE-0001",
        full_name="虚构邀请并发员工",
        work_email="invitation.race@example.invalid",
        department=department,
    )
    admin = User.objects.create_user(
        username="invitation_race_admin",
        password=INITIAL_PASSWORD,
    )
    admin.groups.add(Group.objects.get(name="system_admin"))
    admin_client = APIClient()
    admin_client.force_authenticate(admin)
    created = admin_client.post(
        "/api/v1/accounts/invitations/",
        {
            "employee_id": str(employee.id),
            "username": "invitation.race.employee",
            "email": employee.work_email,
            "target_role": "employee",
        },
        format="json",
    )
    assert created.status_code == 201
    invitation_code = _one_time_code_from_latest_message()

    def accept():
        try:
            return (
                APIClient()
                .post(
                    "/api/v1/auth/invitations/accept/",
                    {"token": invitation_code, "new_password": INITIAL_PASSWORD},
                    format="json",
                )
                .status_code
            )
        finally:
            connections.close_all()

    if connection.vendor == "postgresql":
        barrier = threading.Barrier(2)

        def accept_together():
            barrier.wait(timeout=5)
            return accept()

        with ThreadPoolExecutor(max_workers=2) as executor:
            statuses = list(executor.map(lambda _: accept_together(), range(2)))
    else:
        statuses = [accept(), accept()]

    assert sorted(statuses) == [204, 400]
    employee.refresh_from_db()
    assert employee.user_id is not None
    assert User.objects.filter(username="invitation.race.employee").count() == 1
