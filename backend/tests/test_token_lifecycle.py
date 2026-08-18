import pytest
from rest_framework.test import APIClient

from modules.accounts.models import User
from modules.audit.models import AuditEvent


@pytest.fixture
def token_password():
    return "test-only-token-password-8417"


@pytest.fixture
def token_user(db, token_password):
    return User.objects.create_user(username="token_user", password=token_password)


def login(client, user, password):
    response = client.post(
        "/api/v1/auth/login/",
        {"username": user.username, "password": password},
        format="json",
    )
    assert response.status_code == 200
    return response.json()


@pytest.mark.django_db
def test_refresh_rotates_token_and_rejects_old_refresh_replay(token_user, token_password):
    client = APIClient()
    tokens = login(client, token_user, token_password)

    rotated = client.post(
        "/api/v1/auth/refresh/",
        {"refresh": tokens["refresh"]},
        format="json",
    )
    replay = client.post(
        "/api/v1/auth/refresh/",
        {"refresh": tokens["refresh"]},
        format="json",
    )

    assert rotated.status_code == 200
    assert set(rotated.json()) == {"access", "refresh"}
    assert rotated.json()["refresh"] != tokens["refresh"]
    assert replay.status_code == 401


@pytest.mark.django_db
def test_access_and_refresh_are_rejected_after_user_becomes_inactive(token_user, token_password):
    client = APIClient()
    tokens = login(client, token_user, token_password)
    token_user.is_active = False
    token_user.save(update_fields=["is_active", "updated_at"])

    client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
    me = client.get("/api/v1/me/")
    client.credentials()
    refreshed = client.post(
        "/api/v1/auth/refresh/",
        {"refresh": tokens["refresh"]},
        format="json",
    )

    assert me.status_code == 401
    assert refreshed.status_code == 401


@pytest.mark.django_db
def test_logout_is_idempotent_and_revokes_the_submitted_refresh(token_user, token_password):
    client = APIClient()
    tokens = login(client, token_user, token_password)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")

    first = client.post(
        "/api/v1/auth/logout/",
        {"refresh": tokens["refresh"]},
        format="json",
    )
    second = client.post(
        "/api/v1/auth/logout/",
        {"refresh": tokens["refresh"]},
        format="json",
    )
    client.credentials()
    replay = client.post(
        "/api/v1/auth/refresh/",
        {"refresh": tokens["refresh"]},
        format="json",
    )

    assert first.status_code == 204
    assert first.content == b""
    assert second.status_code == 204
    assert replay.status_code == 401
    assert list(AuditEvent.objects.values_list("action", flat=True)) == ["logout"]


@pytest.mark.django_db
def test_logout_rejects_a_refresh_owned_by_another_user(token_user, token_password):
    other = User.objects.create_user(username="other_token_user", password=token_password)
    client = APIClient()
    own_tokens = login(client, token_user, token_password)
    other_tokens = login(client, other, token_password)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {own_tokens['access']}")

    response = client.post(
        "/api/v1/auth/logout/",
        {"refresh": other_tokens["refresh"]},
        format="json",
    )

    assert response.status_code == 403


@pytest.mark.django_db
def test_logout_all_revokes_only_current_users_outstanding_refresh_tokens(
    token_user,
    token_password,
):
    other = User.objects.create_user(username="other_session_user", password=token_password)
    client = APIClient()
    first = login(client, token_user, token_password)
    second = login(client, token_user, token_password)
    other_tokens = login(client, other, token_password)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {first['access']}")

    revoked = client.post("/api/v1/auth/logout-all/", {}, format="json")
    repeated = client.post("/api/v1/auth/logout-all/", {}, format="json")
    client.credentials()

    assert revoked.status_code == 200
    assert revoked.json() == {"revoked_sessions": 2}
    assert repeated.status_code == 200
    assert repeated.json() == {"revoked_sessions": 0}
    assert list(AuditEvent.objects.values_list("action", flat=True)) == ["logout_all"]
    for refresh in (first["refresh"], second["refresh"]):
        response = client.post("/api/v1/auth/refresh/", {"refresh": refresh}, format="json")
        assert response.status_code == 401
    other_response = client.post(
        "/api/v1/auth/refresh/",
        {"refresh": other_tokens["refresh"]},
        format="json",
    )
    assert other_response.status_code == 200
