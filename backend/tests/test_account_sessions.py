from datetime import timedelta

import pytest
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import AccessToken, RefreshToken

from modules.accounts.models import AccountSession, User


@pytest.fixture
def session_password():
    return "Aster!River7Cobalt"


@pytest.fixture
def session_user(db, session_password):
    return User.objects.create_user(
        username="session_user",
        email="session.user@example.invalid",
        password=session_password,
    )


def login(client, identifier, password, **metadata):
    return client.post(
        "/api/v1/auth/login/",
        {"identifier": identifier, "password": password, **metadata},
        format="json",
    )


@pytest.mark.django_db
def test_email_login_creates_session_and_access_refresh_share_sid(
    session_user,
    session_password,
):
    response = login(
        APIClient(),
        "SESSION.USER@EXAMPLE.INVALID",
        session_password,
        client_platform="windows",
        client_name="Windows 客户端",
        app_version="0.1.0",
    )

    assert response.status_code == 200
    refresh = RefreshToken(response.json()["refresh"])
    access = AccessToken(response.json()["access"])
    session = AccountSession.objects.get(user=session_user)
    assert refresh["sid"] == str(session.id)
    assert access["sid"] == str(session.id)
    assert session.current_refresh_jti == refresh["jti"]
    assert response.json()["session"] == {
        "id": str(session.id),
        "client_platform": "windows",
        "client_name": "Windows 客户端",
        "app_version": "0.1.0",
    }


@pytest.mark.django_db
def test_login_keeps_username_compatibility_but_rejects_both_identifiers(
    session_user,
    session_password,
):
    client = APIClient()
    compatible = client.post(
        "/api/v1/auth/login/",
        {"username": session_user.username, "password": session_password},
        format="json",
    )
    ambiguous = client.post(
        "/api/v1/auth/login/",
        {
            "identifier": session_user.username,
            "username": session_user.username,
            "password": session_password,
        },
        format="json",
    )

    assert compatible.status_code == 200
    assert ambiguous.status_code == 400


@pytest.mark.django_db
def test_refresh_rotation_preserves_sid_updates_jti_and_rejects_replay(
    session_user,
    session_password,
):
    client = APIClient()
    first = login(client, session_user.username, session_password).json()
    first_refresh = RefreshToken(first["refresh"])

    rotated = client.post(
        "/api/v1/auth/refresh/",
        {"refresh": first["refresh"]},
        format="json",
    )
    replay = client.post(
        "/api/v1/auth/refresh/",
        {"refresh": first["refresh"]},
        format="json",
    )

    assert rotated.status_code == 200
    rotated_refresh = RefreshToken(rotated.json()["refresh"])
    assert rotated_refresh["sid"] == first_refresh["sid"]
    session = AccountSession.objects.get(pk=first_refresh["sid"])
    assert session.current_refresh_jti == rotated_refresh["jti"]
    assert replay.status_code == 401


@pytest.mark.django_db
def test_missing_sid_legacy_access_token_is_rejected(session_user):
    legacy_access = AccessToken.for_user(session_user)
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {legacy_access}")

    response = client.get("/api/v1/me/")

    assert response.status_code == 401


@pytest.mark.django_db
def test_revoked_session_invalidates_existing_access_immediately(
    session_user,
    session_password,
):
    tokens = login(APIClient(), session_user.username, session_password).json()
    access = AccessToken(tokens["access"])
    session = AccountSession.objects.get(pk=access["sid"])
    session.revoked_at = timezone.now()
    session.revoked_reason = "test"
    session.save(update_fields=["revoked_at", "revoked_reason"])
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")

    response = client.get("/api/v1/me/")

    assert response.status_code == 401
    assert response.json()["code"] == "session_revoked"


@pytest.mark.django_db
def test_session_authentication_throttles_last_seen_writes(
    session_user,
    session_password,
):
    tokens = login(APIClient(), session_user.username, session_password).json()
    session = AccountSession.objects.get(user=session_user)
    old_seen = timezone.now() - timedelta(minutes=10)
    AccountSession.objects.filter(pk=session.pk).update(last_seen_at=old_seen)
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")

    assert client.get("/api/v1/me/").status_code == 200
    session.refresh_from_db()
    first_seen = session.last_seen_at
    assert first_seen > old_seen
    assert client.get("/api/v1/me/").status_code == 200
    session.refresh_from_db()
    assert session.last_seen_at == first_seen
