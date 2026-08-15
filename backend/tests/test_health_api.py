from unittest.mock import patch

import pytest
from django.db import OperationalError
from rest_framework.test import APIClient


@pytest.mark.django_db
def test_health_returns_public_service_status_when_database_is_available():
    """Catches a broken database probe or accidental health response drift."""
    response = APIClient().get("/api/v1/health/")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "service": "employee-api",
        "version": "0.1.0",
        "database": "ok",
    }


@pytest.mark.django_db
def test_health_hides_database_error_details_when_database_is_unavailable():
    """Catches leaked connection details or a false-positive healthy status."""
    with patch(
        "modules.common.views.connection.cursor",
        side_effect=OperationalError("private-host employee_app secret"),
    ):
        response = APIClient().get("/api/v1/health/")

    assert response.status_code == 503
    assert response.json() == {
        "status": "unavailable",
        "service": "employee-api",
        "version": "0.1.0",
        "database": "unavailable",
    }
    assert "private-host" not in response.content.decode()
    assert "secret" not in response.content.decode()
