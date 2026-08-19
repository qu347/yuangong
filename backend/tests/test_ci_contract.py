from pathlib import Path

import yaml

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "ci.yml"
CHECK_SCRIPT = REPOSITORY_ROOT / "scripts" / "check.ps1"
COMPOSE_FILE = REPOSITORY_ROOT / "deploy" / "docker-compose.dev.yml"
DEV_ENTRYPOINT = REPOSITORY_ROOT / "deploy" / "backend" / "entrypoint.sh"
REPOSITORY_SAFETY_SCRIPT = REPOSITORY_ROOT / "scripts" / "repository-safety.ps1"


def load_workflow():
    return yaml.load(WORKFLOW.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)


def test_ci_has_required_triggers_permissions_concurrency_and_jobs():
    workflow = load_workflow()

    assert set(workflow["on"]) == {"push", "pull_request", "workflow_dispatch"}
    assert workflow["on"]["push"]["branches"] == ["main"]
    assert workflow["on"]["pull_request"]["branches"] == ["main"]
    assert workflow["permissions"] == {"contents": "read"}
    assert workflow["concurrency"]["cancel-in-progress"] == "true"
    assert set(workflow["jobs"]) == {
        "backend-sqlite",
        "backend-postgresql",
        "flutter-quality",
        "android-build",
        "windows-build",
        "repository-safety",
    }


def test_ci_pins_actions_and_required_tool_versions():
    text = WORKFLOW.read_text(encoding="utf-8")

    for sha in (
        "11d5960a326750d5838078e36cf38b85af677262",
        "a26af69be951a213d495a4c3e4e4022e16d87065",
        "cf277c60eb25467037889841efdb72551f06f6c3",
        "1a449444c387b1966244ae4d4f8c696479add0b2",
    ):
        assert f"@{sha}" in text
    assert 'python-version: "3.12"' in text
    assert 'flutter-version: "3.47.0"' in text
    assert 'java-version: "21"' in text
    assert "postgres:17-alpine" in text
    assert "redis:8-alpine" in text


def test_ci_executes_quality_build_schema_migration_and_safety_commands():
    text = WORKFLOW.read_text(encoding="utf-8")

    for command in (
        "ruff format --check",
        "ruff check",
        "manage.py check",
        "makemigrations --check --dry-run",
        "spectacular --validate --fail-on-warn",
        "python -m pytest",
        "dart format --output=none --set-exit-if-changed",
        "flutter analyze",
        "flutter test",
        "flutter build apk --debug",
        "flutter build windows --debug",
        "docker compose -f deploy/docker-compose.dev.yml config --quiet",
        "scripts/repository-safety.ps1",
    ):
        assert command in text
    assert "upload-artifact" not in text


def test_postgresql_ci_actively_probes_redis():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "redis.from_url" in text
    assert ".ping()" in text


def test_local_check_matches_the_full_quality_gate():
    text = CHECK_SCRIPT.read_text(encoding="utf-8")

    for command in (
        "makemigrations --check --dry-run",
        "spectacular --validate --fail-on-warn",
        "TEST_DATABASE_ENGINE=postgresql",
        "EXPECTED_DATABASE_VENDOR=postgresql",
        "python -m pytest -q",
        "repository-safety.ps1",
    ):
        assert command in text


def test_compose_waits_for_redis_and_mailpit_health():
    compose = yaml.load(COMPOSE_FILE.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
    api_dependencies = compose["services"]["api"]["depends_on"]

    assert api_dependencies["redis"]["condition"] == "service_healthy"
    assert api_dependencies["mailpit"]["condition"] == "service_healthy"
    assert compose["services"]["mailpit"]["image"] == "axllent/mailpit:v1.30.7"
    assert compose["services"]["mailpit"]["ports"] == ["127.0.0.1:8025:8025"]


def test_development_entrypoint_honors_one_off_commands():
    text = DEV_ENTRYPOINT.read_text(encoding="utf-8")

    assert 'if [ "$#" -gt 0 ]; then' in text
    assert 'exec "$@"' in text


def test_repository_safety_normalizes_the_success_exit_code():
    text = REPOSITORY_SAFETY_SCRIPT.read_text(encoding="utf-8")

    assert text.rstrip().endswith("exit 0")
