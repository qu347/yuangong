import pytest
from rest_framework.test import APIClient

from modules.accounts.models import User


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("method", "path", "expected_status", "expected_code"),
    [
        ("get", "/api/v1/me/", 401, "authentication_failed"),
        ("get", "/api/v1/employees/?page_size=0", 400, "validation_error"),
        (
            "get",
            "/api/v1/employees/00000000-0000-0000-0000-000000000000/",
            404,
            "not_found",
        ),
    ],
)
def test_api_errors_use_stable_safe_envelope(method, path, expected_status, expected_code):
    client = APIClient()
    if expected_status != 401:
        client.force_authenticate(User.objects.create_user(username=f"error_{expected_status}"))

    response = getattr(client, method)(path, HTTP_X_REQUEST_ID="request-safe-123")

    assert response.status_code == expected_status
    assert response.json()["code"] == expected_code
    assert isinstance(response.json()["message"], str)
    assert "details" in response.json()
    assert response.json()["request_id"] == "request-safe-123"
