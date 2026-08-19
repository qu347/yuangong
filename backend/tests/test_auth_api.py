import pytest
from django.contrib.auth.models import Group
from rest_framework.test import APIClient

from modules.accounts.models import User
from modules.employees.models import Employee
from modules.organizations.models import Department


@pytest.fixture
def login_password():
    return "test-only-password-4827"


@pytest.fixture
def active_user(db, login_password):
    return User.objects.create_user(
        username="directory_demo",
        password=login_password,
        first_name="演示",
        last_name="用户",
    )


@pytest.fixture
def client():
    return APIClient()


def _login(client, active_user, login_password):
    return client.post(
        "/api/v1/auth/login/",
        {"username": active_user.username, "password": login_password},
        format="json",
    )


@pytest.mark.django_db
def test_login_returns_access_and_refresh_tokens(client, active_user, login_password):
    response = _login(client, active_user, login_password)

    assert response.status_code == 200
    assert set(response.json()) == {"access", "refresh", "session"}
    assert all(isinstance(response.json()[name], str) for name in ("access", "refresh"))


@pytest.mark.django_db
def test_login_rejects_invalid_credentials_without_echoing_input(client, active_user):
    response = client.post(
        "/api/v1/auth/login/",
        {"username": active_user.username, "password": "incorrect-test-value"},
        format="json",
    )

    assert response.status_code == 401
    payload = response.content.decode()
    assert active_user.username not in payload
    assert "incorrect-test-value" not in payload


@pytest.mark.django_db
def test_refresh_returns_a_new_access_token(client, active_user, login_password):
    login = _login(client, active_user, login_password)

    response = client.post(
        "/api/v1/auth/refresh/",
        {"refresh": login.json()["refresh"]},
        format="json",
    )

    assert response.status_code == 200
    assert isinstance(response.json()["access"], str)


@pytest.mark.django_db
def test_me_requires_authentication(client):
    response = client.get("/api/v1/me/")

    assert response.status_code == 401


@pytest.mark.django_db
def test_me_returns_clear_null_directory_fields_for_unlinked_user(
    client,
    active_user,
    login_password,
):
    login = _login(client, active_user, login_password)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {login.json()['access']}")

    response = client.get("/api/v1/me/")

    assert response.status_code == 200
    assert response.json() == {
        "id": str(active_user.id),
        "username": "directory_demo",
        "display_name": "演示 用户",
        "employee_id": None,
        "employee_no": None,
        "department": None,
        "roles": [],
        "capabilities": {
            "can_manage_employees": False,
            "can_manage_departments": False,
            "can_manage_positions": False,
            "can_view_audit": False,
            "can_export_audit": False,
            "can_logout_all": True,
            "can_manage_accounts": False,
            "can_invite_accounts": False,
            "can_manage_account_roles": False,
            "can_view_sessions": True,
            "can_revoke_other_sessions": True,
            "can_change_password": True,
        },
    }


@pytest.mark.django_db
def test_me_returns_linked_employee_and_role_summary(client, active_user, login_password):
    department = Department.objects.create(code="MKT", name="市场部")
    employee = Employee.objects.create(
        employee_no="EMP-0099",
        full_name="沈明澈",
        department=department,
        user=active_user,
    )
    active_user.groups.add(Group.objects.create(name="employee"))
    login = _login(client, active_user, login_password)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {login.json()['access']}")

    response = client.get("/api/v1/me/")

    assert response.status_code == 200
    assert response.json()["display_name"] == "沈明澈"
    assert response.json()["employee_id"] == str(employee.id)
    assert response.json()["employee_no"] == "EMP-0099"
    assert response.json()["department"] == {
        "id": str(department.id),
        "code": "MKT",
        "name": "市场部",
    }
    assert response.json()["roles"] == ["employee"]
    assert response.json()["capabilities"] == {
        "can_manage_employees": False,
        "can_manage_departments": False,
        "can_manage_positions": False,
        "can_view_audit": False,
        "can_export_audit": False,
        "can_logout_all": True,
        "can_manage_accounts": False,
        "can_invite_accounts": False,
        "can_manage_account_roles": False,
        "can_view_sessions": True,
        "can_revoke_other_sessions": True,
        "can_change_password": True,
    }
