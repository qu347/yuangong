import hashlib
import hmac
import json
from io import StringIO

import pytest
from django.contrib.auth.models import Group
from django.core.cache import cache
from django.core.management import call_command
from django.test import override_settings

from modules.accounts.models import AccountInvitation, PasswordResetChallenge, User
from modules.employees.models import Employee
from modules.organizations.models import Department

KEYS = {
    "account-token-v1": "test-only-account-token-key-v1",
    "account-token-v2": "test-only-account-token-key-v2",
}


class RecordingNotificationService:
    def __init__(self):
        self.invitation_sent = False
        self.reset_sent = False

    def send_invitation(self, **kwargs):
        assert set(kwargs) == {"email", "token", "expires_at"}
        self.invitation_sent = True

    def send_password_reset(self, **kwargs):
        assert set(kwargs) == {"email", "token", "expires_at"}
        self.reset_sent = True


@override_settings(
    ACCOUNT_TOKEN_HMAC_ACTIVE_KID="account-token-v2",
    ACCOUNT_TOKEN_HMAC_KEYS=KEYS,
    SECRET_KEY="legacy-test-secret-key",
)
def test_new_one_time_token_embeds_active_key_id_and_uses_exact_key():
    from modules.accounts.security_tokens import (
        digest_one_time_token,
        generate_one_time_token,
        token_key_id_from_raw,
    )

    raw_token, digest, key_id = generate_one_time_token("account_invitation")

    assert key_id == "account-token-v2"
    assert raw_token.startswith("account-token-v2.")
    assert token_key_id_from_raw(raw_token) == "account-token-v2"
    assert digest == digest_one_time_token(
        "account_invitation", raw_token, token_key_id="account-token-v2"
    )
    assert raw_token not in digest


@override_settings(
    ACCOUNT_TOKEN_HMAC_ACTIVE_KID="account-token-v2",
    ACCOUNT_TOKEN_HMAC_KEYS=KEYS,
    SECRET_KEY="legacy-test-secret-key",
)
def test_legacy_token_uses_only_django_secret_and_unknown_key_fails():
    from modules.accounts.security_tokens import (
        UnknownTokenKey,
        digest_one_time_token,
        token_key_id_from_raw,
    )

    raw_token = "legacy-token-without-key-id"
    expected = hmac.new(
        b"legacy-test-secret-key",
        f"password_reset\0{raw_token}".encode(),
        hashlib.sha256,
    ).hexdigest()

    assert token_key_id_from_raw(raw_token) is None
    assert digest_one_time_token("password_reset", raw_token, token_key_id=None) == expected
    with pytest.raises(UnknownTokenKey):
        digest_one_time_token(
            "password_reset",
            "unknown-key.token-value",
            token_key_id="unknown-key",
        )


@pytest.mark.django_db
@override_settings(
    ACCOUNT_TOKEN_HMAC_ACTIVE_KID="account-token-v2",
    ACCOUNT_TOKEN_HMAC_KEYS=KEYS,
    SECRET_KEY="legacy-test-secret-key",
)
def test_new_invitation_and_reset_store_active_key_id_and_report_is_safe():
    from modules.accounts.invitation_services import create_invitation
    from modules.accounts.password_services import request_password_reset

    call_command("sync_rbac", verbosity=0)
    department = Department.objects.create(code="KEYRING", name="密钥轮换验证部")
    employee = Employee.objects.create(
        employee_no="KEYRING-1",
        full_name="虚构密钥轮换员工",
        work_email="keyring.employee@example.invalid",
        department=department,
    )
    admin = User.objects.create_user(username="keyring_admin")
    admin.groups.add(Group.objects.get(name="system_admin"))
    notification = RecordingNotificationService()
    invitation = create_invitation(
        actor=admin,
        employee_id=employee.id,
        username="keyring.invited",
        email=employee.work_email,
        target_role="employee",
        notification_service=notification,
    )
    reset_user = User.objects.create_user(
        username="keyring_reset",
        email="keyring.reset@example.invalid",
        password="Aster!River7Cobalt",
    )
    cache.clear()
    assert (
        request_password_reset(
            identifier=reset_user.username,
            notification_service=notification,
        )
        is True
    )

    assert notification.invitation_sent is True
    assert notification.reset_sent is True
    assert invitation.token_key_id == "account-token-v2"
    assert PasswordResetChallenge.objects.get(user=reset_user).token_key_id == "account-token-v2"

    output = StringIO()
    call_command("account_token_key_report", stdout=output)
    report = json.loads(output.getvalue())
    assert report["active_key_id"] == "account-token-v2"
    assert report["valid_invitations_by_key"] == {"account-token-v2": 1}
    assert report["valid_resets_by_key"] == {"account-token-v2": 1}
    assert report["legacy_count"] == 0
    assert "digest" not in output.getvalue().lower()
    assert KEYS["account-token-v2"] not in output.getvalue()


@pytest.mark.django_db
@override_settings(
    ACCOUNT_TOKEN_HMAC_ACTIVE_KID="account-token-v2",
    ACCOUNT_TOKEN_HMAC_KEYS=KEYS,
    SECRET_KEY="legacy-test-secret-key",
)
def test_used_or_revoked_legacy_rows_remain_invalid():
    from django.utils import timezone
    from rest_framework.exceptions import ValidationError

    from modules.accounts.invitation_services import accept_invitation

    department = Department.objects.create(code="LEGACY", name="旧码验证部")
    employee = Employee.objects.create(
        employee_no="LEGACY-1",
        full_name="虚构旧码员工",
        work_email="legacy.employee@example.invalid",
        department=department,
    )
    raw_token = "legacy-revoked-token"
    digest = hmac.new(
        b"legacy-test-secret-key",
        f"account_invitation\0{raw_token}".encode(),
        hashlib.sha256,
    ).hexdigest()
    AccountInvitation.objects.create(
        employee=employee,
        email=employee.work_email,
        username="legacy.invited",
        target_role="employee",
        token_digest=digest,
        token_key_id=None,
        expires_at=timezone.now() + timezone.timedelta(hours=1),
        revoked_at=timezone.now(),
    )

    with pytest.raises(ValidationError):
        accept_invitation(raw_token=raw_token, new_password="Quartz!Forest7Harbor")
    assert employee.user_id is None
