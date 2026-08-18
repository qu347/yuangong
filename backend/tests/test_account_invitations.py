import pytest
from django.contrib.auth.models import Group
from django.core import mail
from django.core.management import call_command
from rest_framework.test import APIClient

from modules.accounts.models import AccountInvitation, User
from modules.employees.models import Employee
from modules.organizations.models import Department


@pytest.fixture
def invitation_data(db):
    call_command("sync_rbac", verbosity=0)
    department = Department.objects.create(code="INV", name="邀请验证部")
    employee = Employee.objects.create(
        employee_no="INV-0001",
        full_name="虚构邀请员工",
        work_email="invite.employee@example.invalid",
        department=department,
    )
    users = {}
    for role in ("employee", "hr_admin", "system_admin"):
        user = User.objects.create_user(username=f"inv_{role}", password="Aster!River7Cobalt")
        user.groups.add(Group.objects.get(name=role))
        users[role] = user
    return employee, users


def client_for(user=None):
    client = APIClient()
    if user is not None:
        client.force_authenticate(user)
    return client


def invitation_token_from_outbox():
    body = mail.outbox[-1].body
    return body.split("一次性代码：", 1)[1].splitlines()[0].strip()


@pytest.mark.django_db
def test_only_system_admin_can_create_invitation_without_token_leak(invitation_data):
    employee, users = invitation_data
    payload = {
        "employee_id": str(employee.id),
        "username": "invited.employee",
        "email": "Invited.Employee@Example.Invalid",
        "target_role": "employee",
    }

    assert (
        client_for().post("/api/v1/accounts/invitations/", payload, format="json").status_code
        == 401
    )
    assert (
        client_for(users["employee"])
        .post("/api/v1/accounts/invitations/", payload, format="json")
        .status_code
        == 403
    )
    assert (
        client_for(users["hr_admin"])
        .post("/api/v1/accounts/invitations/", payload, format="json")
        .status_code
        == 403
    )
    response = client_for(users["system_admin"]).post(
        "/api/v1/accounts/invitations/", payload, format="json"
    )

    assert response.status_code == 201
    assert response.json()["email"] == "invited.employee@example.invalid"
    response_text = response.content.decode().lower()
    assert "token" not in response_text
    assert "digest" not in response_text
    assert len(mail.outbox) == 1
    invitation = AccountInvitation.objects.get(employee=employee)
    assert invitation.token_digest not in mail.outbox[0].body


@pytest.mark.django_db
def test_invitation_accept_is_one_time_and_creates_linked_role_account(invitation_data):
    employee, users = invitation_data
    create = client_for(users["system_admin"]).post(
        "/api/v1/accounts/invitations/",
        {
            "employee_id": str(employee.id),
            "username": "accepted.employee",
            "email": "accepted.employee@example.invalid",
            "target_role": "hr_admin",
        },
        format="json",
    )
    assert create.status_code == 201
    token = invitation_token_from_outbox()
    payload = {"token": token, "new_password": "Quartz!Forest7Harbor"}

    accepted = APIClient().post("/api/v1/auth/invitations/accept/", payload, format="json")
    repeated = APIClient().post("/api/v1/auth/invitations/accept/", payload, format="json")

    assert accepted.status_code == 204
    assert repeated.status_code == 400
    employee.refresh_from_db()
    assert employee.user.username == "accepted.employee"
    assert employee.user.email == "accepted.employee@example.invalid"
    assert employee.user.check_password("Quartz!Forest7Harbor")
    assert list(employee.user.groups.values_list("name", flat=True)) == ["hr_admin"]
    assert AccountInvitation.objects.get(employee=employee).accepted_at is not None


@pytest.mark.django_db
def test_invitation_resend_invalidates_old_code_and_revoke_invalidates_new_code(invitation_data):
    employee, users = invitation_data
    admin_client = client_for(users["system_admin"])
    created = admin_client.post(
        "/api/v1/accounts/invitations/",
        {
            "employee_id": str(employee.id),
            "username": "resend.employee",
            "email": "resend.employee@example.invalid",
            "target_role": "employee",
        },
        format="json",
    ).json()
    old_token = invitation_token_from_outbox()

    resent = admin_client.post(
        f"/api/v1/accounts/invitations/{created['id']}/resend/", {}, format="json"
    )
    new_token = invitation_token_from_outbox()
    old_accept = APIClient().post(
        "/api/v1/auth/invitations/accept/",
        {"token": old_token, "new_password": "Quartz!Forest7Harbor"},
        format="json",
    )
    revoked = admin_client.post(
        f"/api/v1/accounts/invitations/{created['id']}/revoke/", {}, format="json"
    )
    new_accept = APIClient().post(
        "/api/v1/auth/invitations/accept/",
        {"token": new_token, "new_password": "Quartz!Forest7Harbor"},
        format="json",
    )

    assert resent.status_code == 200
    assert new_token != old_token
    assert old_accept.status_code == 400
    assert revoked.json()["changed"] is True
    assert new_accept.status_code == 400


@pytest.mark.django_db
def test_departed_or_linked_employee_cannot_be_invited(invitation_data):
    employee, users = invitation_data
    employee.employment_status = Employee.EmploymentStatus.DEPARTED
    employee.save(update_fields=["employment_status", "updated_at"])
    payload = {
        "employee_id": str(employee.id),
        "username": "invalid.invitation",
        "email": "invalid.invitation@example.invalid",
        "target_role": "employee",
    }

    response = client_for(users["system_admin"]).post(
        "/api/v1/accounts/invitations/", payload, format="json"
    )

    assert response.status_code == 409
