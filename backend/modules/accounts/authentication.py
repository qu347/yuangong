from datetime import timedelta

from django.utils import timezone
from rest_framework.exceptions import AuthenticationFailed
from rest_framework_simplejwt.authentication import JWTAuthentication

from .models import AccountSession


class SessionRevoked(AuthenticationFailed):
    status_code = 401
    default_detail = "会话已失效，请重新登录。"
    default_code = "session_revoked"
    error_code = "session_revoked"


class SessionJWTAuthentication(JWTAuthentication):
    def authenticate(self, request):
        result = super().authenticate(request)
        if result is None:
            return None
        user, validated_token = result
        sid = validated_token.get("sid")
        if not sid:
            raise SessionRevoked()
        try:
            session = AccountSession.objects.get(pk=sid, user=user)
        except (AccountSession.DoesNotExist, ValueError) as error:
            raise SessionRevoked() from error
        now = timezone.now()
        if session.revoked_at is not None or session.expires_at <= now:
            raise SessionRevoked()
        cutoff = now - timedelta(minutes=5)
        if session.last_seen_at <= cutoff:
            AccountSession.objects.filter(
                pk=session.pk,
                revoked_at=None,
                last_seen_at__lte=cutoff,
            ).update(last_seen_at=now)
        request.account_session = session
        return user, validated_token
