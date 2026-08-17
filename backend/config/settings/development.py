from .base import *  # noqa: F403
from .base import env

DEBUG = env.bool("DJANGO_DEBUG", default=True)
ALLOWED_HOSTS = env.list(
    "DJANGO_ALLOWED_HOSTS",
    default=["localhost", "127.0.0.1", "0.0.0.0", "10.0.2.2"],
)
CORS_ALLOWED_ORIGINS = env.list(  # noqa: F405
    "CORS_ALLOWED_ORIGINS",
    default=["http://localhost:3000"],
)
API_DOCS_ENABLED = env.bool("DJANGO_API_DOCS_ENABLED", default=True)
