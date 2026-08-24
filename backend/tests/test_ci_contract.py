from pathlib import Path

import yaml

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "ci.yml"
CHECK_SCRIPT = REPOSITORY_ROOT / "scripts" / "check.ps1"
COMPOSE_FILE = REPOSITORY_ROOT / "deploy" / "docker-compose.dev.yml"
DEV_ENTRYPOINT = REPOSITORY_ROOT / "deploy" / "backend" / "entrypoint.sh"
REPOSITORY_SAFETY_SCRIPT = REPOSITORY_ROOT / "scripts" / "repository-safety.ps1"
DEPENDABOT_FILE = REPOSITORY_ROOT / ".github" / "dependabot.yml"
RELEASE_READINESS_WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "release-readiness.yml"
CODEQL_WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "codeql.yml"
SECURITY_POLICY = REPOSITORY_ROOT / "SECURITY.md"
PR_TEMPLATE = REPOSITORY_ROOT / ".github" / "pull_request_template.md"
GITHUB_GOVERNANCE = REPOSITORY_ROOT / "docs" / "github-governance.md"
RELEASE_CHECKLIST = REPOSITORY_ROOT / "docs" / "release-checklist.md"
CODEQL_ACTION_SHA = "ff2f1c621b7f889edc0d3c761ac2e6a3f8cdb0dd"


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
        "3d3c42e5aac5ba805825da76410c181273ba90b1",
        "5fda3b95a4ea91299a34e894583c3862153e4b97",
        "b6effb05e454b25005698d916606bdc6ffcbf961",
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


def test_dependabot_covers_each_ecosystem_without_auto_merge():
    config = yaml.load(DEPENDABOT_FILE.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
    updates = config["updates"]
    by_ecosystem = {item["package-ecosystem"]: item for item in updates}

    assert set(by_ecosystem) == {"pip", "pub", "github-actions"}
    assert by_ecosystem["pip"]["directory"] == "/backend"
    assert by_ecosystem["pub"]["directory"] == "/apps/employee_app"
    assert by_ecosystem["github-actions"]["directory"] == "/"
    for item in updates:
        assert item["schedule"]["interval"] == "weekly"
        assert item["open-pull-requests-limit"] == "5"
    assert "auto-merge" not in DEPENDABOT_FILE.read_text(encoding="utf-8").lower()


def test_release_readiness_is_manual_non_publishing_and_minimally_privileged():
    workflow = yaml.load(
        RELEASE_READINESS_WORKFLOW.read_text(encoding="utf-8"), Loader=yaml.BaseLoader
    )
    text = RELEASE_READINESS_WORKFLOW.read_text(encoding="utf-8")

    assert set(workflow["on"]) == {"workflow_dispatch"}
    assert workflow["permissions"] == {"contents": "read"}
    assert workflow["concurrency"]["cancel-in-progress"] == "true"
    assert "pull_request_target" not in text
    assert "upload-artifact" not in text
    assert "secrets." not in text
    assert "build-internal-release.ps1" in text
    assert "-ValidationOnly" in text
    assert "docker compose" in text
    assert "Dockerfile.production" in text


def test_codeql_is_python_only_pinned_and_uses_required_permissions():
    workflow = yaml.load(CODEQL_WORKFLOW.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
    text = CODEQL_WORKFLOW.read_text(encoding="utf-8")

    assert set(workflow["on"]) == {"push", "pull_request", "schedule"}
    assert workflow["permissions"] == {"contents": "read", "security-events": "write"}
    assert workflow["jobs"]["analyze"]["strategy"]["matrix"]["language"] == ["python"]
    assert f"github/codeql-action/init@{CODEQL_ACTION_SHA}" in text
    assert f"github/codeql-action/analyze@{CODEQL_ACTION_SHA}" in text
    assert "dart" not in text.lower()
    assert "pull_request_target" not in text


def test_all_governance_workflow_actions_are_pinned_to_full_shas():
    for path in (RELEASE_READINESS_WORKFLOW, CODEQL_WORKFLOW):
        for line in path.read_text(encoding="utf-8").splitlines():
            if "uses:" not in line:
                continue
            reference = line.split("uses:", 1)[1].strip().split()[0]
            assert "@" in reference
            assert len(reference.rsplit("@", 1)[1]) == 40


def test_security_pr_and_governance_documents_record_unapplied_decisions():
    security = SECURITY_POLICY.read_text(encoding="utf-8")
    pr_template = PR_TEMPLATE.read_text(encoding="utf-8")
    governance = GITHUB_GOVERNANCE.read_text(encoding="utf-8")
    release = RELEASE_CHECKLIST.read_text(encoding="utf-8")

    assert "Security Advisories" in security
    assert "mailto:" not in security.lower()
    for phrase in ("依赖", "生产配置", "审计", "发布身份", "外部决策"):
        assert phrase in pr_template
    for phrase in (
        "public",
        "main",
        "未应用",
        "backend-sqlite",
        "backend-postgresql",
        "flutter-quality",
        "android-build",
        "windows-build",
        "repository-safety",
    ):
        assert phrase in governance
    assert "NON-DISTRIBUTABLE" in release
    assert not (REPOSITORY_ROOT / ".github" / "CODEOWNERS").exists()


def test_repository_safety_job_checks_both_compose_contracts():
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "docker-compose.dev.yml config --quiet" in text
    assert "docker-compose.production.example.yml config --quiet" in text


def test_local_check_runs_phase_four_contracts_and_mounts_their_inputs():
    text = CHECK_SCRIPT.read_text(encoding="utf-8")

    for fragment in (
        "test_production_settings.py",
        "test_production_compose.py",
        "test_audit_archive.py",
        "test_release_contract.py",
        "release-scripts.tests.ps1",
        "docker-compose.production.example.yml",
        "${RepositoryRoot}\\SECURITY.md:/app/SECURITY.md:ro",
        "${RepositoryRoot}\\docs:/app/docs:ro",
        "${RepositoryRoot}\\apps:/app/apps:ro",
        "${RepositoryRoot}\\config:/app/config:ro",
    ):
        assert fragment in text
