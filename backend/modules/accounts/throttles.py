import hashlib
import hmac

from django.conf import settings
from django.core.cache import cache
from rest_framework.throttling import SimpleRateThrottle


def hashed_rate_key(scope, raw_value):
    normalized = (raw_value or "").strip().casefold()
    digest = hmac.new(
        settings.SECRET_KEY.encode(),
        f"rate-limit\0{scope}\0{normalized}".encode(),
        hashlib.sha256,
    ).hexdigest()
    return f"account-security:{scope}:{digest}"


def consume_rate_limit(scope, raw_value, *, limit, window_seconds):
    key = hashed_rate_key(scope, raw_value)
    if cache.add(key, 1, timeout=window_seconds):
        return True
    try:
        attempts = cache.incr(key)
    except ValueError:
        cache.set(key, 1, timeout=window_seconds)
        attempts = 1
    return attempts <= limit


class HashedIPRateThrottle(SimpleRateThrottle):
    def get_cache_key(self, request, view):
        del view
        return hashed_rate_key(self.scope, self.get_ident(request))


class LoginRateThrottle(HashedIPRateThrottle):
    scope = "account_login"


class InvitationAcceptRateThrottle(HashedIPRateThrottle):
    scope = "invitation_accept"


class PasswordResetConfirmRateThrottle(HashedIPRateThrottle):
    scope = "password_reset_confirm"
