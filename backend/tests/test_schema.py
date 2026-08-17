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


@pytest.mark.django_db
def test_openapi_schema_describes_jwt_authentication_endpoints():
    response = APIClient().get(
        "/api/schema/",
        HTTP_ACCEPT="application/vnd.oai.openapi+json",
    )

    assert response.status_code == 200
    schema = response.json()
    assert "/api/v1/auth/login/" in schema["paths"]
    assert "/api/v1/auth/refresh/" in schema["paths"]
    assert "/api/v1/me/" in schema["paths"]
    assert schema["components"]["securitySchemes"]["jwtAuth"] == {
        "type": "http",
        "scheme": "bearer",
        "bearerFormat": "JWT",
    }


@pytest.mark.django_db
def test_openapi_schema_documents_directory_routes_and_filters():
    response = APIClient().get(
        "/api/schema/",
        HTTP_ACCEPT="application/vnd.oai.openapi+json",
    )

    schema = response.json()
    for path in (
        "/api/v1/departments/",
        "/api/v1/departments/{id}/",
        "/api/v1/positions/",
        "/api/v1/employees/",
        "/api/v1/employees/{id}/",
    ):
        assert path in schema["paths"]

    employee_parameters = {
        parameter["name"]
        for parameter in schema["paths"]["/api/v1/employees/"]["get"]["parameters"]
    }
    assert {"search", "department", "status", "page", "page_size", "ordering"} <= (
        employee_parameters
    )
