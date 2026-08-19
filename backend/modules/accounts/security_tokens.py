import hashlib
import hmac
import secrets

from django.conf import settings


def digest_one_time_token(purpose, raw_token):
    message = f"{purpose}\0{raw_token}".encode()
    return hmac.new(settings.SECRET_KEY.encode(), message, hashlib.sha256).hexdigest()


def generate_one_time_token(purpose):
    raw_token = secrets.token_urlsafe(32)
    return raw_token, digest_one_time_token(purpose, raw_token)
