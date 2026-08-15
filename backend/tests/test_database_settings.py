import json
import os
import subprocess
import sys

import pytest
from django.db import connection


def test_test_settings_use_postgresql_environment_when_requested():
    """Catches CI starting PostgreSQL while Django silently keeps using SQLite."""
    environment = os.environ.copy()
    environment.update(
        {
            "TEST_DATABASE_ENGINE": "postgresql",
            "POSTGRES_DB": "employee_management_ci",
            "POSTGRES_USER": "employee_ci",
            "POSTGRES_PASSWORD": "test-only-password",
            "POSTGRES_HOST": "postgres-service",
            "POSTGRES_PORT": "55432",
        }
    )
    script = (
        "import json; "
        "from config.settings.test import DATABASES; "
        "print(json.dumps(DATABASES['default'], sort_keys=True))"
    )

    result = subprocess.run(
        [sys.executable, "-c", script],
        cwd=os.path.dirname(os.path.dirname(__file__)),
        env=environment,
        check=True,
        capture_output=True,
        text=True,
    )

    assert json.loads(result.stdout) == {
        "CONN_MAX_AGE": 0,
        "ENGINE": "django.db.backends.postgresql",
        "HOST": "postgres-service",
        "NAME": "employee_management_ci",
        "PASSWORD": "test-only-password",
        "PORT": 55432,
        "USER": "employee_ci",
    }


@pytest.mark.django_db
def test_database_vendor_matches_the_requested_test_backend():
    """Catches an integration job wired to a different database backend."""
    expected_vendor = os.environ.get("EXPECTED_DATABASE_VENDOR", "sqlite")

    assert connection.vendor == expected_vendor
