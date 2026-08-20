import json
import re

from django.core.exceptions import ImproperlyConfigured

KEY_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


def parse_secret_keyring(value, *, setting_name):
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except json.JSONDecodeError as error:
            raise ImproperlyConfigured(f"{setting_name} must be a JSON object") from error
    if not isinstance(value, dict) or not value:
        raise ImproperlyConfigured(f"{setting_name} must be a non-empty JSON object")
    parsed = {}
    for key_id, secret in value.items():
        if not isinstance(key_id, str) or KEY_ID_PATTERN.fullmatch(key_id) is None:
            raise ImproperlyConfigured(f"{setting_name} contains an invalid key id")
        if not isinstance(secret, str) or len(secret) < 16:
            raise ImproperlyConfigured(f"{setting_name} contains an invalid secret value")
        parsed[key_id] = secret
    return parsed


def require_active_key(active_key_id, keys, *, setting_name):
    if not isinstance(active_key_id, str) or active_key_id not in keys:
        raise ImproperlyConfigured(f"{setting_name} active key id is unavailable")
    return active_key_id
