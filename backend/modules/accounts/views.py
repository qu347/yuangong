from django.db import transaction
from drf_spectacular.utils import extend_schema
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from modules.audit.services import record_audit_event

from .serializers import CurrentUserSerializer, LoginSerializer, LogoutSerializer
from .tokens import revoke_all_user_tokens, revoke_refresh_token


class LoginView(TokenObtainPairView):
    authentication_classes = []
    permission_classes = [AllowAny]
    serializer_class = LoginSerializer


class RefreshView(TokenRefreshView):
    authentication_classes = []
    permission_classes = [AllowAny]


class MeView(APIView):
    @extend_schema(responses=CurrentUserSerializer)
    def get(self, request):
        return Response(CurrentUserSerializer(request.user).data)


class LogoutView(APIView):
    @extend_schema(request=LogoutSerializer, responses={204: None})
    def post(self, request):
        serializer = LogoutSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        with transaction.atomic():
            revoked = revoke_refresh_token(serializer.validated_data["refresh"], user=request.user)
            if revoked:
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
    @extend_schema(responses={200: dict})
    def post(self, request):
        with transaction.atomic():
            revoked_sessions = revoke_all_user_tokens(request.user)
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
