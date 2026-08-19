from django.db import transaction
from drf_spectacular.utils import extend_schema, extend_schema_view
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from modules.audit.services import record_audit_event

from .serializers import (
    ActiveUserTokenRefreshSerializer,
    CurrentUserSerializer,
    LoginResponseSerializer,
    LoginSerializer,
    LogoutAllResponseSerializer,
    LogoutSerializer,
)
from .sessions import revoke_all_account_sessions, revoke_session
from .throttles import LoginRateThrottle
from .tokens import revoke_all_user_tokens, revoke_refresh_token, validated_refresh_payload


@extend_schema_view(post=extend_schema(request=LoginSerializer, responses=LoginResponseSerializer))
class LoginView(TokenObtainPairView):
    authentication_classes = []
    permission_classes = [AllowAny]
    serializer_class = LoginSerializer
    throttle_classes = [LoginRateThrottle]


@extend_schema_view(
    post=extend_schema(
        request=ActiveUserTokenRefreshSerializer,
        responses=ActiveUserTokenRefreshSerializer,
    )
)
class RefreshView(TokenRefreshView):
    authentication_classes = []
    permission_classes = [AllowAny]


class MeView(APIView):
    @extend_schema(responses=CurrentUserSerializer)
    def get(self, request):
        return Response(CurrentUserSerializer(request.user).data)


class LogoutView(APIView):
    authentication_classes = [JWTAuthentication]

    @extend_schema(request=LogoutSerializer, responses={204: None})
    def post(self, request):
        serializer = LogoutSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        with transaction.atomic():
            session = request.user.account_sessions.filter(pk=request.auth.get("sid")).first()
            if session is None:
                return Response(status=status.HTTP_204_NO_CONTENT)
            payload = validated_refresh_payload(serializer.validated_data["refresh"])
            if str(payload.get("sid")) != str(session.id):
                from rest_framework.exceptions import PermissionDenied

                raise PermissionDenied("不能用其他会话的 Refresh Token 退出当前会话。")
            session_changed = revoke_session(session, reason="logout")
            revoked = revoke_refresh_token(serializer.validated_data["refresh"], user=request.user)
            if revoked or session_changed:
                record_audit_event(
                    actor=request.user,
                    action="logout",
                    resource_type="user",
                    resource_id=request.user.pk,
                    resource_label=request.user.username,
                    changes={},
                    source="api",
                    request_id=request.headers.get("X-Request-ID"),
                )
        return Response(status=status.HTTP_204_NO_CONTENT)


class LogoutAllView(APIView):
    authentication_classes = [JWTAuthentication]

    @extend_schema(request=None, responses=LogoutAllResponseSerializer)
    def post(self, request):
        with transaction.atomic():
            revoked_sessions = revoke_all_account_sessions(request.user, reason="logout_all")
            revoke_all_user_tokens(request.user)
            if revoked_sessions:
                record_audit_event(
                    actor=request.user,
                    action="logout_all",
                    resource_type="user",
                    resource_id=request.user.pk,
                    resource_label=request.user.username,
                    changes={"revoked_sessions": {"to": revoked_sessions}},
                    source="api",
                    request_id=request.headers.get("X-Request-ID"),
                )
        return Response({"revoked_sessions": revoked_sessions})
