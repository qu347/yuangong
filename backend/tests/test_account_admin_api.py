import pytest
from django.contrib.auth.models import Group
from django.core.management import call_command
from rest_framework.test import APIClient

from modules.accounts.models import AccountSession, User
from modules.employees.models import Employee
from modules.organizations.models import Department

PASSWORD = "Aster!River7Cobalt"


@pytest.fixture
def account_admin_data(db):
    call_command("sync_rbac", verbosity=0)
    department = Department.objects.create(code="ACCOUNT", name="账号验证部")
    employee = Employee.objects.create(
        employee_no="ACCOUNT-1",
        full_name="虚构账号员工",
        work_email="directory.account@example.invalid",
        department=department,
    )
    target = User.objects.create_user(
        username="managed_account",
        email="managed.account@example.invalid",
        password=PASSWORD,
    )
    target.groups.add(Group.objects.get(name="employee"))
    employee.user = target
    employee.save(update_fields=["user", "updated_at"])
    users = {"target": target}
    for role in ("employee", "hr_admin", "system_admin"):
        user = User.objects.create_user(username=f"account_{role}", password=PASSWORD)
        user.groups.add(Group.objects.get(name=role))
        users[role] = user
    return employee, users


def force_client(user=None):
    client = APIClient()
    if user is not None:
        client.force_authenticate(user)
    return client


def login(user):
    return (
        APIClient()
        .post(
            "/api/v1/auth/login/",
            {"identifier": user.username, "password": PASSWORD},
            format="json",
        )
        .json()
    )


@pytest.mark.django_db
def test_account_list_is_system_admin_only(account_admin_data):
    _, users = account_admin_data

    assert force_client().get("/api/v1/accounts/").status_code == 401
    assert force_client(users["employee"]).get("/api/v1/accounts/").status_code == 403
    assert force_client(users["hr_admin"]).get("/api/v1/accounts/").status_code == 403
    response = force_client(users["system_admin"]).get("/api/v1/accounts/")

    assert response.status_code == 200
    assert response.json()["count"] >= 4
    result = next(
        item for item in response.json()["results"] if item["username"] == "managed_account"
    )
    assert result["role"] == "employee"
    assert result["employee"]["employee_no"] == "ACCOUNT-1"
    assert "password" not in result
    assert "groups" not in result


@pytest.mark.django_db
def test_account_email_patch_normalizes_without_writable_lifecycle_fields(account_admin_data):
    _, users = account_admin_data
    target = users["target"]

    response = force_client(users["system_admin"]).patch(
        f"/api/v1/accounts/{target.id}/",
        {
            "email": "  Updated.Account@Example.Invalid  ",
            "is_active": False,
            "is_superuser": True,
            "password": "must-not-be-used",
        },
        format="json",
    )

    assert response.status_code == 200
    target.refresh_from_db()
    assert target.email == "updated.account@example.invalid"
    assert target.is_active is True
    assert target.is_superuser is False
    assert not target.check_password("must-not-be-used")


@pytest.mark.django_db
def test_deactivate_revokes_sessions_without_changing_employee_status(account_admin_data):
    employee, users = account_admin_data
    target = users["target"]
    tokens = login(target)

    response = force_client(users["system_admin"]).post(
        f"/api/v1/accounts/{target.id}/deactivate/", {}, format="json"
    )

    assert response.status_code == 200
    target.refresh_from_db()
    employee.refresh_from_db()
    assert target.is_active is False
    assert employee.employment_status == Employee.EmploymentStatus.ACTIVE
    assert AccountSession.objects.get(user=target).revoked_at is not None
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
    assert client.get("/api/v1/me/").status_code == 401


@pytest.mark.django_db
def test_cannot_deactivate_self_or_manage_superuser_or_system_admin(account_admin_data):
    _, users = account_admin_data
    system_admin = users["system_admin"]
    superuser = User.objects.create_superuser(username="protected_superuser", password=PASSWORD)

    self_response = force_client(system_admin).post(
        f"/api/v1/accounts/{system_admin.id}/deactivate/", {}, format="json"
    )
    super_response = force_client(system_admin).post(
        f"/api/v1/accounts/{superuser.id}/deactivate/", {}, format="json"
    )

    assert self_response.status_code == 409
    assert super_response.status_code == 409


@pytest.mark.django_db
def test_activate_requires_active_employee_and_does_not_restore_old_session(account_admin_data):
    employee, users = account_admin_data
    target = users["target"]
    target.is_active = False
    target.save(update_fields=["is_active", "updated_at"])
    employee.employment_status = Employee.EmploymentStatus.DEPARTED
    employee.save(update_fields=["employment_status", "updated_at"])
    client = force_client(users["system_admin"])

    blocked = client.post(f"/api/v1/accounts/{target.id}/activate/", {}, format="json")
    employee.employment_status = Employee.EmploymentStatus.ACTIVE
    employee.save(update_fields=["employment_status", "updated_at"])
    activated = client.post(f"/api/v1/accounts/{target.id}/activate/", {}, format="json")

    assert blocked.status_code == 409
    assert activated.status_code == 200
    target.refresh_from_db()
    assert target.is_active is True
    assert not AccountSession.objects.filter(user=target, revoked_at=None).exists()


@pytest.mark.django_db
def test_role_change_allows_only_employee_or_hr_admin_and_revokes_sessions(account_admin_data):
    _, users = account_admin_data
    target = users["target"]
    login(target)
    client = force_client(users["system_admin"])

    changed = client.post(
        f"/api/v1/accounts/{target.id}/change-role/",
        {"role": "hr_admin"},
        format="json",
    )
    forbidden = client.post(
        f"/api/v1/accounts/{target.id}/change-role/",
        {"role": "system_admin"},
        format="json",
    )

    assert changed.status_code == 200
    assert changed.json()["role"] == "hr_admin"
    assert forbidden.status_code == 400
    assert list(target.groups.values_list("name", flat=True)) == ["hr_admin"]
    assert AccountSession.objects.get(user=target).revoked_at is not None


@pytest.mark.django_db
def test_me_exposes_account_capabilities_from_permissions(account_admin_data):
    _, users = account_admin_data
    system_response = force_client(users["system_admin"]).get("/api/v1/me/")
    hr_response = force_client(users["hr_admin"]).get("/api/v1/me/")

    for name in (
        "can_manage_accounts",
        "can_invite_accounts",
        "can_manage_account_roles",
    ):
        assert system_response.json()["capabilities"][name] is True
        assert hr_response.json()["capabilities"][name] is False
    assert hr_response.json()["capabilities"]["can_view_sessions"] is True
    assert hr_response.json()["capabilities"]["can_change_password"] is True
