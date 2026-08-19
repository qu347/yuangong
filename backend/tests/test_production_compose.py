from pathlib import Path

import yaml

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
COMPOSE_FILE = REPOSITORY_ROOT / "deploy" / "docker-compose.production.example.yml"
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
