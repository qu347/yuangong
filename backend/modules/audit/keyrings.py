from django.conf import settings


class ArchiveKeyError(Exception):
    pass


def get_archive_key(key_id):
    keys = settings.AUDIT_ARCHIVE_HMAC_KEYS
    key = keys.get(key_id) if isinstance(keys, dict) else None
    if not isinstance(key, str) or not key:
        raise ArchiveKeyError("Archive HMAC key is unavailable.")
    return key.encode("utf-8")


def get_active_archive_key():
    key_id = settings.AUDIT_ARCHIVE_HMAC_ACTIVE_KID
    if not isinstance(key_id, str) or not key_id:
        raise ArchiveKeyError("Archive HMAC active key id is unavailable.")
    return key_id, get_archive_key(key_id)
