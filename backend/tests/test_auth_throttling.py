from django.core.cache import cache
from django.test import override_settings


@override_settings(SECRET_KEY="test-only-throttle-secret")
def test_rate_limit_cache_key_never_contains_raw_identifier():
    from modules.accounts.throttles import hashed_rate_key

    raw_identifier = "Sensitive.User@Example.Invalid"
    key = hashed_rate_key("password_reset", raw_identifier)

    assert raw_identifier.casefold() not in key.casefold()
    assert "sensitive.user" not in key.casefold()
    assert key.startswith("account-security:password_reset:")


def test_fixed_window_rate_limit_stops_after_configured_attempts():
    from modules.accounts.throttles import consume_rate_limit

    cache.clear()
    assert consume_rate_limit("test", "client", limit=2, window_seconds=60) is True
    assert consume_rate_limit("test", "client", limit=2, window_seconds=60) is True
    assert consume_rate_limit("test", "client", limit=2, window_seconds=60) is False
