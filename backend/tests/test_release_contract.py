import hashlib
import json
import subprocess
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPOSITORY_ROOT / "scripts"
IDENTITY_SCRIPT = SCRIPTS / "validate-release-identity.ps1"
BUILD_SCRIPT = SCRIPTS / "build-internal-release.ps1"
VERIFY_SCRIPT = SCRIPTS / "verify-release-artifacts.ps1"
GRADLE_FILE = REPOSITORY_ROOT / "apps" / "employee_app" / "android" / "app" / "build.gradle.kts"


def run_powershell(script: Path, *arguments: str):
    return subprocess.run(
        [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(script),
            *arguments,
        ],
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )


def test_release_identity_rejects_placeholders_but_supports_explicit_validation_mode():
    strict = run_powershell(
        IDENTITY_SCRIPT,
        "-ConfigFile",
        str(REPOSITORY_ROOT / "config" / "release.validation.json"),
        "-AsJson",
    )
    assert strict.returncode != 0
    assert "yourcompany" not in (strict.stdout + strict.stderr).lower()

    validation = run_powershell(
        IDENTITY_SCRIPT,
        "-ConfigFile",
        str(REPOSITORY_ROOT / "config" / "release.validation.json"),
        "-AllowDevelopmentPlaceholders",
        "-AsJson",
    )
    assert validation.returncode == 0, validation.stderr
    result = json.loads(validation.stdout)
    assert result["validation_only"] is True
    assert result["version"] == "0.1.0"
    assert result["build_number"] == 1
    assert result["api_base_url_scheme"] == "https"
    assert result["reasons"]


def test_release_identity_rejects_http_even_when_placeholders_are_allowed(tmp_path):
    config = tmp_path / "http.json"
    config.write_text(
        json.dumps(
            {
                "APP_ENV": "release-validation",
                "API_BASE_URL": "http://validation.invalid/api/v1",
                "PRODUCT_NAME": "Validation Product",
                "SUPPORT_EMAIL": "support@validation.invalid",
            }
        ),
        encoding="utf-8",
    )

    result = run_powershell(
        IDENTITY_SCRIPT,
        "-ConfigFile",
        str(config),
        "-AllowDevelopmentPlaceholders",
        "-AsJson",
    )
    assert result.returncode != 0
    assert "http://validation.invalid" not in (result.stdout + result.stderr)


def test_android_release_signing_is_environment_only_and_cannot_fall_back_to_debug():
    text = GRADLE_FILE.read_text(encoding="utf-8")

    for variable in (
        "ANDROID_KEYSTORE_PATH",
        "ANDROID_KEYSTORE_PASSWORD",
        "ANDROID_KEY_ALIAS",
        "ANDROID_KEY_PASSWORD",
    ):
        assert f'System.getenv("{variable}")' in text
    assert 'signingConfigs.getByName("debug")' not in text
    assert "release signing environment is incomplete" in text


def test_build_script_enforces_external_fresh_output_and_validation_marking():
    text = BUILD_SCRIPT.read_text(encoding="utf-8")

    for fragment in (
        'ValidateSet("android", "windows", "all")',
        "AllowDevelopmentPlaceholders",
        "ValidationOnly",
        "NON-DISTRIBUTABLE",
        "ANDROID_KEYSTORE_PATH",
        "WINDOWS-UNSIGNED-NON-DISTRIBUTABLE.zip",
        "TrackFileAccess",
        "manifest.json",
        "SHA256SUMS.txt",
        "git rev-parse HEAD",
    ):
        assert fragment in text
    assert "Remove-Item $OutputDirectory" not in text


def test_release_verifier_accepts_exact_manifest_then_detects_tampering(tmp_path):
    artifact = tmp_path / "ANDROID-NON-DISTRIBUTABLE.apk"
    artifact.write_bytes(b"validation artifact")
    digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
    manifest = {
        "schema_version": 1,
        "product_name": "Validation Product",
        "version": "0.1.0",
        "build_number": 1,
        "git_commit": "a" * 40,
        "built_at": "2026-08-19T00:00:00Z",
        "validation_only": True,
        "api_base_url_scheme": "https",
        "artifacts": [
            {
                "platform": "android",
                "filename": artifact.name,
                "size": artifact.stat().st_size,
                "sha256": digest,
                "signed": True,
                "signing_identity": "sha256:" + "b" * 64,
            }
        ],
    }
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    (tmp_path / "SHA256SUMS.txt").write_text(f"{digest}  {artifact.name}\n", encoding="ascii")

    valid = run_powershell(VERIFY_SCRIPT, "-ManifestPath", str(manifest_path))
    assert valid.returncode == 0, valid.stderr

    artifact.write_bytes(b"tampered artifact")
    tampered = run_powershell(VERIFY_SCRIPT, "-ManifestPath", str(manifest_path))
    assert tampered.returncode != 0
    assert "validation artifact" not in (tampered.stdout + tampered.stderr)


def test_release_verifier_rejects_unlisted_files(tmp_path):
    artifact = tmp_path / "WINDOWS-UNSIGNED-NON-DISTRIBUTABLE.zip"
    artifact.write_bytes(b"zip placeholder")
    digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
    (tmp_path / "unexpected.txt").write_text("unexpected", encoding="utf-8")
    manifest = {
        "schema_version": 1,
        "product_name": "Validation Product",
        "version": "0.1.0",
        "build_number": 1,
        "git_commit": "a" * 40,
        "built_at": "2026-08-19T00:00:00Z",
        "validation_only": True,
        "api_base_url_scheme": "https",
        "artifacts": [
            {
                "platform": "windows",
                "filename": artifact.name,
                "size": artifact.stat().st_size,
                "sha256": digest,
                "signed": False,
                "signing_identity": None,
            }
        ],
    }
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    (tmp_path / "SHA256SUMS.txt").write_text(f"{digest}  {artifact.name}\n", encoding="ascii")

    result = run_powershell(VERIFY_SCRIPT, "-ManifestPath", str(manifest_path))
    assert result.returncode != 0
