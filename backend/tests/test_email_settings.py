from django.conf import settings


def test_test_environment_uses_in_memory_email_and_cache_backends():
    assert settings.EMAIL_BACKEND == "django.core.mail.backends.locmem.EmailBackend"
    assert settings.CACHES["default"]["BACKEND"] == (
        "django.core.cache.backends.locmem.LocMemCache"
    )


def test_security_lifetimes_are_centralized_in_settings():
    assert settings.ACCOUNT_INVITATION_TTL.total_seconds() == 48 * 60 * 60
    assert settings.PASSWORD_RESET_TTL.total_seconds() == 30 * 60
