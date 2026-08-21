import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

BACKEND_ROOT = os.path.dirname(os.path.dirname(__file__))
REPOSITORY_ROOT = Path(BACKEND_ROOT).parent


def minimal_environment():
    return {
        name: os.environ[name]
        for name in ("PATH", "SYSTEMROOT", "TEMP", "TMP")
        if name in os.environ
    }


def valid_production_environment():
    environment = minimal_environment()
    environment.update(
        {
            "DJANGO_SETTINGS_MODULE": "config.settings.production",
            "DJANGO_SECRET_KEY": "django-production-contract-" + "A7!" * 24,
            "JWT_SIGNING_KEY": "jwt-production-contract-" + "B8!" * 24,
            "DJANGO_ALLOWED_HOSTS": "pilot.internal.example.com",
            "CORS_ALLOWED_ORIGINS": "https://pilot.internal.example.com",
            "POSTGRES_DB": "employee_management",
            "POSTGRES_USER": "employee_app",
            "POSTGRES_PASSWORD": "test-only-database-contract-value",
            "POSTGRES_HOST": "db",
            "POSTGRES_PORT": "5432",
            "REDIS_URL": "redis://redis:6379/0",
            "EMAIL_HOST": "smtp.internal.example.com",
            "EMAIL_PORT": "587",
            "EMAIL_HOST_USER": "smtp-contract-user",
            "EMAIL_HOST_PASSWORD": "test-only-smtp-contract-value",
            "EMAIL_USE_TLS": "true",
            "EMAIL_USE_SSL": "false",
            "EMAIL_TIMEOUT": "10",
            "DEFAULT_FROM_EMAIL": "no-reply@internal.example.com",
            "SERVER_EMAIL": "server@internal.example.com",
            "API_PUBLIC_BASE_URL": "https://pilot.internal.example.com/api/v1",
            "ACCOUNT_TOKEN_HMAC_ACTIVE_KID": "account-token-v1",
            "ACCOUNT_TOKEN_HMAC_KEYS_JSON": json.dumps(
                {"account-token-v1": "test-only-account-contract-value"}
            ),
            "AUDIT_ARCHIVE_HMAC_ACTIVE_KID": "audit-archive-v1",
            "AUDIT_ARCHIVE_HMAC_KEYS_JSON": json.dumps(
                {"audit-archive-v1": "test-only-archive-contract-value"}
            ),
            "AUDIT_ARCHIVE_DIR": str(
                Path("D:/EmployeeAuditArchives/ProductionContract")
                if os.name == "nt"
                else Path("/tmp/employee-audit-archives-contract")
            ),
            "EMPLOYEE_ATTACHMENT_STORAGE_ROOT": str(
                Path("D:/EmployeeAttachmentStorage/ProductionContract")
                if os.name == "nt"
                else Path("/tmp/employee-attachment-storage-contract")
            ),
        }
    )
    return environment


def run_production_import(environment):
    script = (
        "import json; from config.settings import production as p; "
        "print(json.dumps({'debug':p.DEBUG,'db':p.DATABASES['default']['ENGINE'],"
        "'cache':p.CACHES['default']['BACKEND'],'jwt_separate':"
        "p.SIMPLE_JWT['SIGNING_KEY'] != p.SECRET_KEY,'api':p.API_PUBLIC_BASE_URL},sort_keys=True))"
    )
    return subprocess.run(
        [sys.executable, "-c", script],
        cwd=BACKEND_ROOT,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )


def test_complete_production_environment_is_secure_and_deploy_check_passes():
    environment = valid_production_environment()

    imported = run_production_import(environment)
    checked = subprocess.run(
        [
            sys.executable,
            "manage.py",
            "check",
            "--deploy",
            "--settings=config.settings.production",
        ],
        cwd=BACKEND_ROOT,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )

    assert imported.returncode == 0, imported.stderr
    assert json.loads(imported.stdout) == {
        "api": "https://pilot.internal.example.com/api/v1",
        "cache": "django.core.cache.backends.redis.RedisCache",
        "db": "django.db.backends.postgresql",
        "debug": False,
        "jwt_separate": True,
    }
    assert checked.returncode == 0, checked.stdout + checked.stderr


@pytest.mark.parametrize(
    ("mutation", "value"),
    [
        ("JWT_SIGNING_KEY", None),
        ("API_PUBLIC_BASE_URL", "http://pilot.internal.example.com/api/v1"),
        ("DJANGO_ALLOWED_HOSTS", "*"),
        ("EMAIL_HOST", "mailpit"),
        ("DEFAULT_FROM_EMAIL", "no-reply@example.invalid"),
        ("EMAIL_USE_SSL", "true"),
        ("ACCOUNT_TOKEN_HMAC_ACTIVE_KID", "unknown-account-key"),
        ("AUDIT_ARCHIVE_HMAC_ACTIVE_KID", "unknown-archive-key"),
    ],
)
def test_invalid_production_contract_is_rejected_without_echoing_secrets(mutation, value):
    environment = valid_production_environment()
    if value is None:
        environment.pop(mutation)
    else:
        environment[mutation] = value

    result = run_production_import(environment)
    combined = result.stdout + result.stderr

    assert result.returncode != 0
    for secret_name in (
        "DJANGO_SECRET_KEY",
        "JWT_SIGNING_KEY",
        "POSTGRES_PASSWORD",
        "EMAIL_HOST_PASSWORD",
    ):
        assert environment.get(secret_name, "not-present") not in combined


def test_production_rejects_attachment_root_inside_repository():
    environment = valid_production_environment()
    environment["EMPLOYEE_ATTACHMENT_STORAGE_ROOT"] = str(REPOSITORY_ROOT / "storage")

    result = run_production_import(environment)

    assert result.returncode != 0
    assert "outside the repository" in result.stderr


def test_production_requires_attachment_root():
    environment = valid_production_environment()
    environment.pop("EMPLOYEE_ATTACHMENT_STORAGE_ROOT")

    result = run_production_import(environment)

    assert result.returncode != 0
    assert "EMPLOYEE_ATTACHMENT_STORAGE_ROOT" in result.stderr


def test_production_rejects_attachment_root_shared_with_audit_archives():
    environment = valid_production_environment()
    environment["EMPLOYEE_ATTACHMENT_STORAGE_ROOT"] = environment["AUDIT_ARCHIVE_DIR"]

    result = run_production_import(environment)

    assert result.returncode != 0
    assert "must not share" in result.stderr
