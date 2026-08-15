from django.conf import settings


def test_development_cors_uses_an_explicit_origin_list():
    """Catches an unsafe allow-all CORS configuration."""
    assert settings.CORS_ALLOW_ALL_ORIGINS is False
    assert settings.CORS_ALLOWED_ORIGINS == ["http://localhost:3000"]
    assert "corsheaders" in settings.INSTALLED_APPS


def test_test_server_allows_loopback_http_verification():
    """Catches a test server configuration that rejects real loopback probes."""
    assert "127.0.0.1" in settings.ALLOWED_HOSTS
