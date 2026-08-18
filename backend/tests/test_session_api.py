import pytest
from rest_framework.test import APIClient

from modules.accounts.models import AccountSession, User
from modules.audit.models import AuditEvent


@pytest.fixture
def session_api_password():
    return "Aster!River7Cobalt"


@pytest.fixture
def session_api_user(db, session_api_password):
    return User.objects.create_user(
        username="session_api_user",
        email="session.api@example.invalid",
        password=session_api_password,
    )


def login(user, password, platform):
    client = APIClient()
    response = client.post(
        "/api/v1/auth/login/",
        {
            "identifier": user.username,
            "password": password,
            "client_platform": platform,
            "client_name": f"{platform} client",
        },
        format="json",
    )
    assert response.status_code == 200
    return response.json()


def authenticated(access):
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    return client


@pytest.mark.django_db
def test_session_list_returns_only_current_user_and_marks_current(
    session_api_user,
    session_api_password,
):
    first = login(session_api_user, session_api_password, "windows")
    second = login(session_api_user, session_api_password, "android")
    other = User.objects.create_user(username="other_session_owner", password=session_api_password)
    login(other, session_api_password, "unknown")

    response = authenticated(first["access"]).get("/api/v1/auth/sessions/")

    assert response.status_code == 200
    assert len(response.json()) == 2
    assert {item["client_platform"] for item in response.json()} == {"windows", "android"}
    assert sum(item["is_current"] for item in response.json()) == 1
    assert (
        next(item for item in response.json() if item["is_current"])["id"] == first["session"]["id"]
    )
    forbidden_keys = {"current_refresh_jti", "jti", "token", "authorization"}
    assert all(forbidden_keys.isdisjoint(item) for item in response.json())
    assert second["session"]["id"] != first["session"]["id"]


@pytest.mark.django_db
def test_revoke_other_session_invalidates_its_access_but_keeps_current(
    session_api_user,
    session_api_password,
):
    current = login(session_api_user, session_api_password, "windows")
    other = login(session_api_user, session_api_password, "android")
    client = authenticated(current["access"])

    revoked = client.post(
        f"/api/v1/auth/sessions/{other['session']['id']}/revoke/",
        {},
        format="json",
    )

    assert revoked.status_code == 200
    assert revoked.json() == {"changed": True, "is_current": False}
    assert client.get("/api/v1/me/").status_code == 200
    assert authenticated(other["access"]).get("/api/v1/me/").status_code == 401
    assert list(AuditEvent.objects.values_list("action", flat=True)) == ["session_revoked"]


@pytest.mark.django_db
def test_cross_user_session_revoke_does_not_reveal_session(
    session_api_user,
    session_api_password,
):
    current = login(session_api_user, session_api_password, "windows")
    other_user = User.objects.create_user(
        username="cross_session_user", password=session_api_password
    )
    other = login(other_user, session_api_password, "android")

    response = authenticated(current["access"]).post(
        f"/api/v1/auth/sessions/{other['session']['id']}/revoke/",
        {},
        format="json",
    )

    assert response.status_code == 404


@pytest.mark.django_db
def test_revoke_others_is_idempotent_and_preserves_current_session(
    session_api_user,
    session_api_password,
):
    current = login(session_api_user, session_api_password, "windows")
    login(session_api_user, session_api_password, "android")
    login(session_api_user, session_api_password, "unknown")
    client = authenticated(current["access"])

    first = client.post("/api/v1/auth/sessions/revoke-others/", {}, format="json")
    second = client.post("/api/v1/auth/sessions/revoke-others/", {}, format="json")

    assert first.status_code == 200
    assert first.json() == {"revoked_sessions": 2}
    assert second.json() == {"revoked_sessions": 0}
    assert client.get("/api/v1/me/").status_code == 200


@pytest.mark.django_db
def test_logout_revokes_current_session_and_access_immediately(
    session_api_user,
    session_api_password,
):
    tokens = login(session_api_user, session_api_password, "windows")
    client = authenticated(tokens["access"])

    response = client.post(
        "/api/v1/auth/logout/",
        {"refresh": tokens["refresh"]},
        format="json",
    )

    assert response.status_code == 204
    session = AccountSession.objects.get(pk=tokens["session"]["id"])
    assert session.revoked_at is not None
    assert client.get("/api/v1/me/").status_code == 401
