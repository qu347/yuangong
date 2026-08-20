import os

from django.conf import settings
from django.core.checks import Error, Tags, register


@register(Tags.security, deploy=True)
def production_security_contract(app_configs, **kwargs):
    del app_configs, kwargs
    if not os.environ.get("DJANGO_SETTINGS_MODULE", "").endswith(".production"):
        return []
    errors = []
    checks = (
        (settings.DEBUG is False, "production DEBUG must be False", "common.E001"),
        (
            settings.API_PUBLIC_BASE_URL.startswith("https://"),
            "production API_PUBLIC_BASE_URL must use HTTPS",
            "common.E002",
        ),
        (
            settings.DATABASES["default"]["ENGINE"] == "django.db.backends.postgresql",
            "production database must be PostgreSQL",
            "common.E003",
        ),
        (
            settings.CACHES["default"]["BACKEND"] == "django.core.cache.backends.redis.RedisCache",
            "production cache must be Redis",
            "common.E004",
        ),
        (
            settings.SIMPLE_JWT["SIGNING_KEY"] != settings.SECRET_KEY,
            "JWT signing key must be separate from Django SECRET_KEY",
            "common.E005",
        ),
    )
    for passed, message, check_id in checks:
        if not passed:
            errors.append(Error(message, id=check_id))
    return errors
