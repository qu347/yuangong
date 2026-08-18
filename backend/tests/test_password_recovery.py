from datetime import timedelta

import pytest
from django.core import mail
from django.utils import timezone
from rest_framework.test import APIClient

from modules.accounts.models import AccountSession, PasswordResetChallenge, User
from modules.audit.models import AuditEvent

PASSWORD = "Aster!River7Cobalt"
NEW_PASSWORD = "Quartz!Forest7Harbor"


def reset_token_from_outbox():
    return mail.outbox[-1].body.split("一次性代码：", 1)[1].splitlines()[0].strip()


def login(user, password=PASSWORD):
    return APIClient().post(
        "/api/v1/auth/login/",
        {"identifier": user.username, "password": password},
        format="json",
    )


@pytest.mark.django_db
def test_password_reset_request_always_returns_same_202_and_only_valid_account_gets_mail():
    valid = User.objects.create_user(
        username="reset_valid",
        email="reset.valid@example.invalid",
        password=PASSWORD,
    )
    User.objects.create_user(
        username="reset_inactive",
        email="reset.inactive@example.invalid",
        password=PASSWORD,
        is_active=False,
    )
    client = APIClient()

    missing = client.post(
        "/api/v1/auth/password-reset/request/", {"identifier": "missing"}, format="json"
    )
    inactive = client.post(
        "/api/v1/auth/password-reset/request/",
        {"identifier": "reset_inactive"},
        format="json",
    )
    sent = client.post(
        "/api/v1/auth/password-reset/request/",
        {"identifier": valid.email.upper()},
        format="json",
    )

    assert missing.status_code == inactive.status_code == sent.status_code == 202
    assert missing.json() == inactive.json() == sent.json()
    assert len(mail.outbox) == 1
    assert PasswordResetChallenge.objects.filter(user=valid).count() == 1


@pytest.mark.django_db
def test_password_reset_code_is_one_time_and_revokes_existing_sessions():
    user = User.objects.create_user(
        username="reset_once",
        email="reset.once@example.invalid",
        password=PASSWORD,
    )
    session_login = login(user).json()
    request = APIClient().post(
        "/api/v1/auth/password-reset/request/",
        {"identifier": user.username},
        format="json",
    )
    assert request.status_code == 202
    token = reset_token_from_outbox()

    confirmed = APIClient().post(
        "/api/v1/auth/password-reset/confirm/",
        {"token": token, "new_password": NEW_PASSWORD},
        format="json",
    )
    repeated = APIClient().post(
        "/api/v1/auth/password-reset/confirm/",
        {"token": token, "new_password": NEW_PASSWORD},
        format="json",
    )

    assert confirmed.status_code == 204
    assert repeated.status_code == 400
    user.refresh_from_db()
    assert user.check_password(NEW_PASSWORD)
    assert not user.check_password(PASSWORD)
    assert AccountSession.objects.get(user=user).revoked_at is not None
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {session_login['access']}")
    assert client.get("/api/v1/me/").status_code == 401
    assert AuditEvent.objects.filter(action="password_reset_completed").count() == 1


@pytest.mark.django_db
def test_authenticated_password_change_requires_current_password_and_revokes_current_session():
    user = User.objects.create_user(
        username="change_password",
        email="change.password@example.invalid",
        password=PASSWORD,
    )
    tokens = login(user).json()
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")

    wrong = client.post(
        "/api/v1/auth/password/change/",
        {"current_password": "wrong-password", "new_password": NEW_PASSWORD},
        format="json",
    )
    changed = client.post(
        "/api/v1/auth/password/change/",
        {"current_password": PASSWORD, "new_password": NEW_PASSWORD},
        format="json",
    )

    assert wrong.status_code == 400
    assert changed.status_code == 204
    user.refresh_from_db()
    assert user.check_password(NEW_PASSWORD)
    assert client.get("/api/v1/me/").status_code == 401
    assert AuditEvent.objects.filter(action="password_changed").count() == 1


@pytest.mark.django_db
def test_new_password_reset_request_revokes_old_code_and_expired_code_fails():
    user = User.objects.create_user(
        username="reset_rotation",
        email="reset.rotation@example.invalid",
        password=PASSWORD,
    )
    client = APIClient()
    first = client.post(
        "/api/v1/auth/password-reset/request/",
        {"identifier": user.username},
        format="json",
    )
    assert first.status_code == 202
    old_token = reset_token_from_outbox()
    second = client.post(
        "/api/v1/auth/password-reset/request/",
        {"identifier": user.username},
        format="json",
    )
    assert second.status_code == 202
    new_token = reset_token_from_outbox()

    old_confirm = client.post(
        "/api/v1/auth/password-reset/confirm/",
        {"token": old_token, "new_password": NEW_PASSWORD},
        format="json",
    )
    assert old_confirm.status_code == 400
    challenge = PasswordResetChallenge.objects.get(revoked_at=None, used_at=None)
    challenge.expires_at = timezone.now() - timedelta(seconds=1)
    challenge.save(update_fields=["expires_at"])
    expired_confirm = client.post(
        "/api/v1/auth/password-reset/confirm/",
        {"token": new_token, "new_password": NEW_PASSWORD},
        format="json",
    )

    assert expired_confirm.status_code == 400
    user.refresh_from_db()
    assert user.check_password(PASSWORD)
