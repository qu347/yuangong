import pytest
from rest_framework.test import APIClient


@pytest.mark.django_db
def test_openapi_schema_includes_health_endpoint():
    """Catches an API route that disappears from the generated contract."""
    response = APIClient().get(
        "/api/schema/",
        HTTP_ACCEPT="application/vnd.oai.openapi+json",
    )

    assert response.status_code == 200
    assert "/api/v1/health/" in response.json()["paths"]
