from datetime import UTC, datetime

from django.db import transaction
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework_simplejwt.settings import api_settings
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken
from rest_framework_simplejwt.tokens import RefreshToken, TokenError


def validated_refresh_payload(raw_token):
    try:
        unverified = RefreshToken(raw_token, verify=False)
        payload = unverified.get_token_backend().decode(raw_token, verify=True)
        if payload.get(api_settings.TOKEN_TYPE_CLAIM) != RefreshToken.token_type:
            raise TokenError("Token has wrong type")
        if api_settings.JTI_CLAIM not in payload or api_settings.USER_ID_CLAIM not in payload:
            raise TokenError("Token has missing claims")
        return payload
    except TokenError as error:
        raise ValidationError({"refresh": "Refresh Token 无效或已过期。"}) from error


@transaction.atomic
def revoke_refresh_token(raw_token, *, user):
    payload = validated_refresh_payload(raw_token)
    if str(payload[api_settings.USER_ID_CLAIM]) != str(getattr(user, api_settings.USER_ID_FIELD)):
        raise PermissionDenied("不能吊销其他用户的会话。")

    outstanding, _ = OutstandingToken.objects.get_or_create(
        jti=payload[api_settings.JTI_CLAIM],
        defaults={
            "user": user,
            "token": raw_token,
            "created_at": datetime.now(tz=UTC),
            "expires_at": datetime.fromtimestamp(payload["exp"], tz=UTC),
        },
    )
    if outstanding.user_id is not None and outstanding.user_id != user.pk:
        raise PermissionDenied("不能吊销其他用户的会话。")
    _, created = BlacklistedToken.objects.get_or_create(token=outstanding)
    return created


@transaction.atomic
def revoke_all_user_tokens(user):
    outstanding_tokens = (
        OutstandingToken.objects.filter(
            user=user,
            blacklistedtoken__isnull=True,
        )
        .order_by("pk")
        .select_for_update(of=("self",))
    )
    revoked_sessions = 0
    for outstanding in outstanding_tokens:
        _, created = BlacklistedToken.objects.get_or_create(token=outstanding)
        revoked_sessions += int(created)
    return revoked_sessions
