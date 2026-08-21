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
    assert schema["components"]["securitySchemes"]["sessionJwtAuth"] == {
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


@pytest.mark.django_db
def test_openapi_schema_documents_phase_five_product_endpoints():
    schema = APIClient().get("/api/schema/", HTTP_ACCEPT="application/vnd.oai.openapi+json").json()

    for path in (
        "/api/v1/dashboard/summary/",
        "/api/v1/statistics/hr/",
        "/api/v1/departments/tree/",
        "/api/v1/search/",
        "/api/v1/notifications/",
        "/api/v1/notifications/{notification_id}/read/",
    ):
        assert path in schema["paths"]

    employee_fields = schema["components"]["schemas"]["EmployeeDetail"]["properties"]
    assert {
        "avatar_url",
        "gender",
        "birthday",
        "office_location",
        "manager",
        "description",
    } <= set(employee_fields)


@pytest.mark.django_db
def test_openapi_schema_documents_management_actions_with_json_responses():
    response = APIClient().get(
        "/api/schema/",
        HTTP_ACCEPT="application/vnd.oai.openapi+json",
    )

    schema = response.json()
    for path in (
        "/api/v1/auth/logout-all/",
        "/api/v1/departments/{id}/activate/",
        "/api/v1/departments/{id}/deactivate/",
        "/api/v1/positions/{id}/activate/",
        "/api/v1/positions/{id}/deactivate/",
        "/api/v1/employees/{id}/depart/",
        "/api/v1/employees/{id}/reactivate/",
    ):
        operation = schema["paths"][path]["post"]
        success = operation["responses"]["200"]
        assert success["content"]["application/json"]["schema"]


@pytest.mark.django_db
def test_openapi_schema_documents_session_tokens_and_flat_role_response():
    schema = (
        APIClient()
        .get(
            "/api/schema/",
            HTTP_ACCEPT="application/vnd.oai.openapi+json",
        )
        .json()
    )

    login = schema["components"]["schemas"]["LoginResponse"]["properties"]
    refresh = schema["components"]["schemas"]["ActiveUserTokenRefresh"]["properties"]
    role = schema["components"]["schemas"]["AccountRoleChangeResponse"]["properties"]
    assert {"access", "refresh", "session"} <= set(login)
    assert {"access", "refresh"} <= set(refresh)
    assert {"id", "username", "role", "changed", "is_manageable"} <= set(role)


@pytest.mark.django_db
def test_openapi_schema_documents_audit_export_filters_and_csv_response():
    schema = (
        APIClient()
        .get(
            "/api/schema/",
            HTTP_ACCEPT="application/vnd.oai.openapi+json",
        )
        .json()
    )

    operation = schema["paths"]["/api/v1/audit-events/export.csv"]["get"]
    assert {
        "actor",
        "action",
        "resource_type",
        "resource_id",
        "source",
        "created_after",
        "created_before",
        "ordering",
    } <= {parameter["name"] for parameter in operation["parameters"]}
    assert "text/csv" in operation["responses"]["200"]["content"]


@pytest.mark.django_db
def test_openapi_schema_documents_attachment_list_download_and_delete_contracts():
    schema = (
        APIClient()
        .get(
            "/api/schema/",
            HTTP_ACCEPT="application/vnd.oai.openapi+json",
        )
        .json()
    )

    list_path = "/api/v1/employees/{employee_id}/attachments/"
    download_path = "/api/v1/attachments/{attachment_id}/download/"
    detail_path = "/api/v1/attachments/{attachment_id}/"
    assert {list_path, download_path, detail_path} <= set(schema["paths"])

    listed = schema["paths"][list_path]["get"]["responses"]["200"]
    listed_schema = listed["content"]["application/json"]["schema"]
    listed_schema = schema["components"]["schemas"][
        listed_schema["$ref"].removeprefix("#/components/schemas/")
    ]
    assert listed_schema["type"] == "object"
    assert {"count", "next", "previous", "results"} <= set(listed_schema["properties"])
    assert listed_schema["properties"]["results"]["items"] == {
        "$ref": "#/components/schemas/EmployeeAttachment"
    }

    download = schema["paths"][download_path]["get"]["responses"]["200"]
    expected_download_content_types = {
        "application/pdf",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "image/jpeg",
        "image/png",
    }
    assert set(download["content"]) == expected_download_content_types
    assert all(
        media["schema"] == {"type": "string", "format": "binary"}
        for media in download["content"].values()
    )

    deleted = schema["paths"][detail_path]["delete"]["responses"]["204"]
    assert "content" not in deleted
