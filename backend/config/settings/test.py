from .base import *  # noqa: F403
from .base import env

SECRET_KEY = "test-only-secret-key-with-at-least-32-bytes"
DEBUG = False
ALLOWED_HOSTS = ["testserver", "localhost", "127.0.0.1"]
CORS_ALLOWED_ORIGINS = ["http://localhost:3000"]  # noqa: F405
API_DOCS_ENABLED = True

if env("TEST_DATABASE_ENGINE", default="sqlite") == "postgresql":
    DATABASES = {  # noqa: F405
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": env("POSTGRES_DB"),
            "USER": env("POSTGRES_USER"),
            "PASSWORD": env("POSTGRES_PASSWORD"),
            "HOST": env("POSTGRES_HOST"),
            "PORT": env.int("POSTGRES_PORT", default=5432),
            "CONN_MAX_AGE": 0,
        }
    }
else:
    DATABASES = {  # noqa: F405
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": ":memory:",
        }
    }

PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
