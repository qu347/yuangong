import pytest
from django.apps import apps
from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction
from django.utils import timezone

from modules.accounts.models import User
from modules.employees.models import Employee
from modules.organizations.models import Department


@pytest.mark.django_db
def test_user_normalizes_non_empty_account_email():
    user = User.objects.create_user(
        username="email_normalization_user",
        email="  Account.Owner@Example.Invalid  ",
    )

    user.refresh_from_db()

    assert user.email == "account.owner@example.invalid"


@pytest.mark.django_db
def test_non_empty_account_email_is_case_insensitively_unique_but_blank_repeats():
    User.objects.create_user(username="email_first", email="owner@example.invalid")
    User.objects.create_user(username="blank_first", email="")
    User.objects.create_user(username="blank_second", email="")

    with pytest.raises(IntegrityError), transaction.atomic():
        User.objects.create_user(username="email_second", email="OWNER@EXAMPLE.INVALID")


@pytest.mark.django_db
def test_account_security_models_keep_only_safe_session_and_digest_fields():
    AccountInvitation = apps.get_model("accounts", "AccountInvitation")
    PasswordResetChallenge = apps.get_model("accounts", "PasswordResetChallenge")
    AccountSession = apps.get_model("accounts", "AccountSession")
    department = Department.objects.create(code="SECURITY", name="安全验证部")
    employee = Employee.objects.create(
        employee_no="SEC-0001",
        full_name="虚构安全员工",
        work_email="security.employee@example.invalid",
        department=department,
    )
    creator = User.objects.create_user(username="security_creator")
    expires_at = timezone.now() + timezone.timedelta(hours=1)

    invitation = AccountInvitation.objects.create(
        employee=employee,
        email="security.employee@example.invalid",
        username="security_employee",
        target_role="employee",
        token_digest="a" * 64,
        expires_at=expires_at,
        created_by=creator,
    )
    challenge = PasswordResetChallenge.objects.create(
        user=creator,
        token_digest="b" * 64,
        expires_at=expires_at,
        requested_from="app",
    )
    session = AccountSession.objects.create(
        user=creator,
        expires_at=expires_at,
        client_platform="windows",
        client_name="Windows 客户端",
        app_version="0.1.0",
    )

    assert invitation.target_role == "employee"
    assert challenge.requested_from == "app"
    assert session.current_refresh_jti == ""
    model_field_names = {field.name for field in AccountSession._meta.fields}
    assert {"access_token", "refresh_token", "authorization", "ip_address"}.isdisjoint(
        model_field_names
    )


@pytest.mark.django_db
def test_invitation_rejects_system_admin_target_role():
    AccountInvitation = apps.get_model("accounts", "AccountInvitation")
    department = Department.objects.create(code="SEC-ROLE", name="安全角色部")
    employee = Employee.objects.create(
        employee_no="SEC-ROLE-1",
        full_name="虚构角色员工",
        department=department,
    )
    invitation = AccountInvitation(
        employee=employee,
        email="role@example.invalid",
        username="role_target",
        target_role="system_admin",
        token_digest="c" * 64,
        expires_at=timezone.now() + timezone.timedelta(hours=1),
    )

    with pytest.raises(ValidationError):
        invitation.full_clean()


def test_one_time_token_digest_is_purpose_scoped_and_never_equals_raw_token():
    from modules.accounts.security_tokens import digest_one_time_token, generate_one_time_token

    raw_token, invitation_digest = generate_one_time_token("account_invitation")
    reset_digest = digest_one_time_token("password_reset", raw_token)

    assert raw_token
    assert len(invitation_digest) == 64
    assert invitation_digest != raw_token
    assert reset_digest != invitation_digest
