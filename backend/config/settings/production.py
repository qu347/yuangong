from django.core.exceptions import ImproperlyConfigured

from .base import *  # noqa: F403
from .base import env

DEBUG = False
SECRET_KEY = env("DJANGO_SECRET_KEY")
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS")
CORS_ALLOWED_ORIGINS = env.list("CORS_ALLOWED_ORIGINS")  # noqa: F405
API_DOCS_ENABLED = env.bool("DJANGO_API_DOCS_ENABLED", default=False)
EMAIL_BACKEND = env("DJANGO_EMAIL_BACKEND")
EMAIL_HOST = env("DJANGO_EMAIL_HOST")
EMAIL_PORT = env.int("DJANGO_EMAIL_PORT")
DEFAULT_FROM_EMAIL = env("DJANGO_DEFAULT_FROM_EMAIL")

required_database_variables = {
    "POSTGRES_DB": env("POSTGRES_DB"),
    "POSTGRES_USER": env("POSTGRES_USER"),
    "POSTGRES_PASSWORD": env("POSTGRES_PASSWORD"),
    "POSTGRES_HOST": env("POSTGRES_HOST"),
    "POSTGRES_PORT": env.int("POSTGRES_PORT"),
}

if not ALLOWED_HOSTS:
    raise ImproperlyConfigured("DJANGO_ALLOWED_HOSTS must not be empty in production")

DATABASES = {  # noqa: F405
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": required_database_variables["POSTGRES_DB"],
        "USER": required_database_variables["POSTGRES_USER"],
        "PASSWORD": required_database_variables["POSTGRES_PASSWORD"],
        "HOST": required_database_variables["POSTGRES_HOST"],
        "PORT": required_database_variables["POSTGRES_PORT"],
        "CONN_MAX_AGE": 60,
    }
}

SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "same-origin"
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
