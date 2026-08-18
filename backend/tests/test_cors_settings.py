import json
import os
import subprocess
import sys

from django.conf import settings


def test_development_cors_uses_an_explicit_origin_list():
    """Catches an unsafe allow-all CORS configuration."""
    assert settings.CORS_ALLOW_ALL_ORIGINS is False
    assert settings.CORS_ALLOWED_ORIGINS == ["http://localhost:3000"]
    assert "corsheaders" in settings.INSTALLED_APPS


def test_test_server_allows_loopback_http_verification():
    """Catches a test server configuration that rejects real loopback probes."""
    assert "127.0.0.1" in settings.ALLOWED_HOSTS


def test_development_allows_android_emulator_host():
    environment = {
        name: os.environ[name]
        for name in ("PATH", "SYSTEMROOT", "TEMP", "TMP")
        if name in os.environ
    }
    script = (
        "import json; "
        "from config.settings.development import ALLOWED_HOSTS; "
        "print(json.dumps(ALLOWED_HOSTS))"
    )

    result = subprocess.run(
        [sys.executable, "-c", script],
        cwd=os.path.dirname(os.path.dirname(__file__)),
        env=environment,
        check=True,
        capture_output=True,
        text=True,
    )

    assert "10.0.2.2" in json.loads(result.stdout)
