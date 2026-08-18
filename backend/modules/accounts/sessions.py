from dataclasses import dataclass

from django.conf import settings
from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import AuthenticationFailed
from rest_framework_simplejwt.settings import api_settings
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken
from rest_framework_simplejwt.tokens import RefreshToken, TokenError

from .models import AccountSession, User


@dataclass(frozen=True)
class IssuedSessionTokens:
    access: str
    refresh: str
    session: AccountSession


def _update_outstanding_token(refresh, user):
    OutstandingToken.objects.filter(
        user=user,
        jti=refresh[api_settings.JTI_CLAIM],
    ).update(token=str(refresh))


@transaction.atomic
def issue_session_tokens(
    user,
    *,
    platform=AccountSession.ClientPlatform.UNKNOWN,
    client_name="",
    app_version="",
):
    expires_at = timezone.now() + settings.SIMPLE_JWT["REFRESH_TOKEN_LIFETIME"]
    session = AccountSession.objects.create(
        user=user,
        expires_at=expires_at,
        client_platform=platform,
        client_name=client_name,
        app_version=app_version,
    )
    refresh = RefreshToken.for_user(user)
    refresh["sid"] = str(session.id)
    _update_outstanding_token(refresh, user)
    session.current_refresh_jti = refresh[api_settings.JTI_CLAIM]
    session.save(update_fields=["current_refresh_jti"])
    return IssuedSessionTokens(
        access=str(refresh.access_token),
        refresh=str(refresh),
        session=session,
    )


def _refresh_user(refresh):
    user_id = refresh.get(api_settings.USER_ID_CLAIM)
    if not user_id:
        raise AuthenticationFailed("Refresh Token 无效或已过期。")
    try:
        user = User.objects.get(**{api_settings.USER_ID_FIELD: user_id})
    except User.DoesNotExist as error:
        raise AuthenticationFailed("Refresh Token 无效或已过期。") from error
    if not user.is_active:
        raise AuthenticationFailed("账号已停用，无法刷新会话。")
    return user


@transaction.atomic
def rotate_session_refresh(raw_refresh):
    try:
        refresh = RefreshToken(raw_refresh)
    except TokenError as error:
        raise AuthenticationFailed("Refresh Token 无效或已过期。") from error
    sid = refresh.get("sid")
    if not sid:
        raise AuthenticationFailed("会话已失效，请重新登录。", code="session_revoked")
    user = _refresh_user(refresh)
    try:
        session = AccountSession.objects.select_for_update().get(pk=sid, user=user)
    except (AccountSession.DoesNotExist, ValueError) as error:
        raise AuthenticationFailed("会话已失效，请重新登录。", code="session_revoked") from error
    now = timezone.now()
    if session.revoked_at is not None or session.expires_at <= now:
        raise AuthenticationFailed("会话已失效，请重新登录。", code="session_revoked")
    if session.current_refresh_jti != refresh[api_settings.JTI_CLAIM]:
        raise AuthenticationFailed("会话已失效，请重新登录。", code="session_revoked")

    refresh.blacklist()
    rotated = RefreshToken.for_user(user)
    rotated["sid"] = str(session.id)
    _update_outstanding_token(rotated, user)
    session.current_refresh_jti = rotated[api_settings.JTI_CLAIM]
    session.save(update_fields=["current_refresh_jti"])
    return {"access": str(rotated.access_token), "refresh": str(rotated)}


def _blacklist_current_refresh(session):
    if not session.current_refresh_jti:
        return False
    outstanding = OutstandingToken.objects.filter(
        user=session.user,
        jti=session.current_refresh_jti,
    ).first()
    if outstanding is None:
        return False
    _, created = BlacklistedToken.objects.get_or_create(token=outstanding)
    return created


@transaction.atomic
def revoke_session(session, *, reason):
    locked = AccountSession.objects.select_for_update().select_related("user").get(pk=session.pk)
    if locked.revoked_at is not None:
        return False
    locked.revoked_at = timezone.now()
    locked.revoked_reason = reason
    locked.save(update_fields=["revoked_at", "revoked_reason"])
    _blacklist_current_refresh(locked)
    return True


@transaction.atomic
def revoke_all_account_sessions(user, *, reason, exclude_sid=None):
    sessions = AccountSession.objects.select_for_update().filter(user=user, revoked_at=None)
    if exclude_sid is not None:
        sessions = sessions.exclude(pk=exclude_sid)
    revoked = 0
    for session in sessions.select_related("user"):
        session.revoked_at = timezone.now()
        session.revoked_reason = reason
        session.save(update_fields=["revoked_at", "revoked_reason"])
        _blacklist_current_refresh(session)
        revoked += 1
    return revoked
