from pathlib import Path

import yaml

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
COMPOSE_FILE = REPOSITORY_ROOT / "deploy" / "docker-compose.production.example.yml"
DEVELOPMENT_COMPOSE_FILE = REPOSITORY_ROOT / "deploy" / "docker-compose.dev.yml"
DOCKERFILE = REPOSITORY_ROOT / "deploy" / "backend" / "Dockerfile.production"
ENTRYPOINT = REPOSITORY_ROOT / "deploy" / "backend" / "entrypoint.production.sh"


def test_production_compose_is_internal_non_mailpit_and_health_checked():
    compose = yaml.safe_load(COMPOSE_FILE.read_text(encoding="utf-8"))

    assert set(compose["services"]) == {"api", "db", "redis"}
    assert "ports" not in compose["services"]["db"]
    assert "ports" not in compose["services"]["redis"]
    assert compose["services"]["api"]["build"]["dockerfile"] == (
        "deploy/backend/Dockerfile.production"
    )
    assert compose["services"]["api"]["healthcheck"]
    assert compose["services"]["api"]["restart"] == "unless-stopped"
    assert "mailpit" not in COMPOSE_FILE.read_text(encoding="utf-8").casefold()


def test_production_image_runs_non_root_without_automatic_migration_or_runserver():
    dockerfile = DOCKERFILE.read_text(encoding="utf-8")
    entrypoint = ENTRYPOINT.read_text(encoding="utf-8")

    assert "USER app" in dockerfile
    assert "requirements/base.txt" in dockerfile
    assert "gunicorn" in dockerfile
    assert "runserver" not in dockerfile
    assert "migrate" not in entrypoint
    assert 'exec "$@"' in entrypoint


def test_production_healthcheck_marks_internal_http_as_forwarded_https():
    compose = yaml.safe_load(COMPOSE_FILE.read_text(encoding="utf-8"))
    api = compose["services"]["api"]
    health_command = " ".join(api["healthcheck"]["test"])

    assert api["environment"]["DJANGO_TRUST_X_FORWARDED_PROTO"] == "true"
    assert "X-Forwarded-Proto" in health_command
    assert "https" in health_command


def test_compose_mounts_durable_private_employee_attachment_storage():
    for compose_file in (DEVELOPMENT_COMPOSE_FILE, COMPOSE_FILE):
        compose = yaml.safe_load(compose_file.read_text(encoding="utf-8"))
        api = compose["services"]["api"]

        assert api["environment"]["EMPLOYEE_ATTACHMENT_STORAGE_ROOT"] == (
            "/data/employee-attachments"
        )
        assert "attachment_data:/data/employee-attachments" in api["volumes"]
        assert "attachment_data" in compose["volumes"]


def test_production_image_prepares_attachment_mount_for_non_root_runtime():
    dockerfile = DOCKERFILE.read_text(encoding="utf-8")

    assert "install -d -m 0700 -o app -g app /data/employee-attachments" in dockerfile
