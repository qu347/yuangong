import hashlib
import hmac
import secrets

from django.conf import settings

from modules.common.keyrings import KEY_ID_PATTERN


class UnknownTokenKey(Exception):
    pass


def token_key_id_from_raw(raw_token):
    if "." not in raw_token:
        return None
    key_id, token_value = raw_token.split(".", 1)
    if KEY_ID_PATTERN.fullmatch(key_id) is None or not token_value:
        raise UnknownTokenKey("One-time token key id is invalid.")
    return key_id


def _key_for_id(key_id):
    if key_id is None:
        return settings.SECRET_KEY.encode("utf-8")
    keys = settings.ACCOUNT_TOKEN_HMAC_KEYS
    key = keys.get(key_id) if isinstance(keys, dict) else None
    if not isinstance(key, str) or not key:
        raise UnknownTokenKey("One-time token key id is unknown.")
    return key.encode("utf-8")


def digest_one_time_token(purpose, raw_token, *, token_key_id=None):
    parsed_key_id = token_key_id_from_raw(raw_token)
    if parsed_key_id != token_key_id:
        raise UnknownTokenKey("One-time token key id does not match the token.")
    message = f"{purpose}\0{raw_token}".encode()
    return hmac.new(_key_for_id(token_key_id), message, hashlib.sha256).hexdigest()


def generate_one_time_token(purpose):
    key_id = settings.ACCOUNT_TOKEN_HMAC_ACTIVE_KID
    if not isinstance(key_id, str) or KEY_ID_PATTERN.fullmatch(key_id) is None:
        raise UnknownTokenKey("One-time token active key id is invalid.")
    random_value = secrets.token_urlsafe(32)
    raw_token = f"{key_id}.{random_value}"
    return (
        raw_token,
        digest_one_time_token(purpose, raw_token, token_key_id=key_id),
        key_id,
    )
