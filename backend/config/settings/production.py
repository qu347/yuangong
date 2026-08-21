from pathlib import Path
from urllib.parse import urlparse

from django.core.exceptions import ImproperlyConfigured, ValidationError
from django.core.validators import validate_email

from modules.common.keyrings import parse_secret_keyring, require_active_key

from .base import *  # noqa: F403
from .base import PROJECT_ROOT, env


def invalid(message):
    raise ImproperlyConfigured(message)


DEBUG = False
SECRET_KEY = env("DJANGO_SECRET_KEY")
JWT_SIGNING_KEY = env("JWT_SIGNING_KEY")
if JWT_SIGNING_KEY == SECRET_KEY:
    invalid("JWT_SIGNING_KEY must be separate from DJANGO_SECRET_KEY")

ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS")
if not ALLOWED_HOSTS or "*" in ALLOWED_HOSTS:
    invalid("DJANGO_ALLOWED_HOSTS must be non-empty and cannot contain a wildcard")
CORS_ALLOWED_ORIGINS = env.list("CORS_ALLOWED_ORIGINS")  # noqa: F405
if not CORS_ALLOWED_ORIGINS or any(
    origin == "*" or urlparse(origin).scheme != "https" for origin in CORS_ALLOWED_ORIGINS
):
    invalid("CORS_ALLOWED_ORIGINS must contain explicit HTTPS origins")

API_PUBLIC_BASE_URL = env("API_PUBLIC_BASE_URL").rstrip("/")
public_api = urlparse(API_PUBLIC_BASE_URL)
if public_api.scheme != "https" or not public_api.hostname:
    invalid("API_PUBLIC_BASE_URL must be an absolute HTTPS URL")

DATABASES = {  # noqa: F405
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": env("POSTGRES_DB"),
        "USER": env("POSTGRES_USER"),
        "PASSWORD": env("POSTGRES_PASSWORD"),
        "HOST": env("POSTGRES_HOST"),
        "PORT": env.int("POSTGRES_PORT"),
        "CONN_MAX_AGE": 60,
    }
}
REDIS_URL = env("REDIS_URL")
CACHES = {  # noqa: F405
    "default": {
        "BACKEND": "django.core.cache.backends.redis.RedisCache",
        "LOCATION": REDIS_URL,
    }
}

EMAIL_BACKEND = "django.core.mail.backends.smtp.EmailBackend"
EMAIL_HOST = env("EMAIL_HOST")
if EMAIL_HOST.casefold() in {"mailpit", "localhost", "127.0.0.1"}:
    invalid("Production EMAIL_HOST cannot use Mailpit or localhost")
EMAIL_PORT = env.int("EMAIL_PORT")
EMAIL_HOST_USER = env("EMAIL_HOST_USER")
EMAIL_HOST_PASSWORD = env("EMAIL_HOST_PASSWORD")
EMAIL_USE_TLS = env.bool("EMAIL_USE_TLS")
EMAIL_USE_SSL = env.bool("EMAIL_USE_SSL")
if EMAIL_USE_TLS and EMAIL_USE_SSL:
    invalid("EMAIL_USE_TLS and EMAIL_USE_SSL cannot both be enabled")
EMAIL_TIMEOUT = env.int("EMAIL_TIMEOUT")
if EMAIL_TIMEOUT <= 0:
    invalid("EMAIL_TIMEOUT must be positive")
DEFAULT_FROM_EMAIL = env("DEFAULT_FROM_EMAIL")
SERVER_EMAIL = env("SERVER_EMAIL")
for setting_name, address in (
    ("DEFAULT_FROM_EMAIL", DEFAULT_FROM_EMAIL),
    ("SERVER_EMAIL", SERVER_EMAIL),
):
    try:
        validate_email(address)
    except ValidationError as error:
        raise ImproperlyConfigured(f"{setting_name} must be a valid email address") from error
    if address.casefold().endswith(".invalid"):
        invalid(f"{setting_name} cannot use an .invalid address")

ACCOUNT_TOKEN_HMAC_ACTIVE_KID = env("ACCOUNT_TOKEN_HMAC_ACTIVE_KID")
ACCOUNT_TOKEN_HMAC_KEYS = parse_secret_keyring(
    env("ACCOUNT_TOKEN_HMAC_KEYS_JSON"), setting_name="ACCOUNT_TOKEN_HMAC_KEYS_JSON"
)
require_active_key(
    ACCOUNT_TOKEN_HMAC_ACTIVE_KID,
    ACCOUNT_TOKEN_HMAC_KEYS,
    setting_name="ACCOUNT_TOKEN_HMAC_KEYS_JSON",
)

AUDIT_ARCHIVE_HMAC_ACTIVE_KID = env("AUDIT_ARCHIVE_HMAC_ACTIVE_KID")
AUDIT_ARCHIVE_HMAC_KEYS = parse_secret_keyring(
    env("AUDIT_ARCHIVE_HMAC_KEYS_JSON"),
    setting_name="AUDIT_ARCHIVE_HMAC_KEYS_JSON",
)
require_active_key(
    AUDIT_ARCHIVE_HMAC_ACTIVE_KID,
    AUDIT_ARCHIVE_HMAC_KEYS,
    setting_name="AUDIT_ARCHIVE_HMAC_KEYS_JSON",
)
if set(ACCOUNT_TOKEN_HMAC_KEYS.values()) & set(AUDIT_ARCHIVE_HMAC_KEYS.values()):
    invalid("Account token and audit archive keyrings must not reuse secrets")
if SECRET_KEY in ACCOUNT_TOKEN_HMAC_KEYS.values() or SECRET_KEY in AUDIT_ARCHIVE_HMAC_KEYS.values():
    invalid("Django SECRET_KEY must not be reused by HMAC keyrings")
if (
    JWT_SIGNING_KEY in ACCOUNT_TOKEN_HMAC_KEYS.values()
    or JWT_SIGNING_KEY in AUDIT_ARCHIVE_HMAC_KEYS.values()
):
    invalid("JWT_SIGNING_KEY must not be reused by HMAC keyrings")

AUDIT_ARCHIVE_DIR = Path(env("AUDIT_ARCHIVE_DIR")).resolve()
repository_root = Path(PROJECT_ROOT).resolve()
if (
    not AUDIT_ARCHIVE_DIR.is_absolute()
    or AUDIT_ARCHIVE_DIR == repository_root
    or repository_root in AUDIT_ARCHIVE_DIR.parents
):
    invalid("AUDIT_ARCHIVE_DIR must be an absolute path outside the repository")

attachment_storage_root = Path(env("EMPLOYEE_ATTACHMENT_STORAGE_ROOT"))
if not attachment_storage_root.is_absolute():
    invalid("EMPLOYEE_ATTACHMENT_STORAGE_ROOT must be an absolute path outside the repository")
EMPLOYEE_ATTACHMENT_STORAGE_ROOT = attachment_storage_root.resolve()
if (
    EMPLOYEE_ATTACHMENT_STORAGE_ROOT == repository_root
    or repository_root in EMPLOYEE_ATTACHMENT_STORAGE_ROOT.parents
):
    invalid("EMPLOYEE_ATTACHMENT_STORAGE_ROOT must be an absolute path outside the repository")
if EMPLOYEE_ATTACHMENT_STORAGE_ROOT == AUDIT_ARCHIVE_DIR:
    invalid("EMPLOYEE_ATTACHMENT_STORAGE_ROOT must not share AUDIT_ARCHIVE_DIR")

SIMPLE_JWT["SIGNING_KEY"] = JWT_SIGNING_KEY  # noqa: F405
API_DOCS_ENABLED = env.bool("DJANGO_API_DOCS_ENABLED", default=False)
SECURE_SSL_REDIRECT = True
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "same-origin"
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
CSRF_TRUSTED_ORIGINS = [f"{public_api.scheme}://{public_api.netloc}"]
if env.bool("DJANGO_TRUST_X_FORWARDED_PROTO", default=False):
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
