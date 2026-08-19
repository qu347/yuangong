from drf_spectacular.utils import extend_schema
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from .password_serializers import (
    PasswordChangeSerializer,
    PasswordResetAcceptedSerializer,
    PasswordResetConfirmSerializer,
    PasswordResetRequestSerializer,
)
from .password_services import change_password, confirm_password_reset, request_password_reset
from .throttles import PasswordResetConfirmRateThrottle

GENERIC_RESET_MESSAGE = "如果账号符合条件，系统会发送密码重置邮件。"


class PasswordResetRequestView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]

    @extend_schema(
        request=PasswordResetRequestSerializer,
        responses={202: PasswordResetAcceptedSerializer},
    )
    def post(self, request):
        serializer = PasswordResetRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        request_password_reset(identifier=serializer.validated_data["identifier"])
        return Response({"message": GENERIC_RESET_MESSAGE}, status=status.HTTP_202_ACCEPTED)


class PasswordResetConfirmView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [PasswordResetConfirmRateThrottle]

    @extend_schema(request=PasswordResetConfirmSerializer, responses={204: None})
    def post(self, request):
        serializer = PasswordResetConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        confirm_password_reset(
            raw_token=serializer.validated_data["token"],
            new_password=serializer.validated_data["new_password"],
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class PasswordChangeView(APIView):
    @extend_schema(request=PasswordChangeSerializer, responses={204: None})
    def post(self, request):
        serializer = PasswordChangeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        change_password(
            user=request.user,
            current_password=serializer.validated_data["current_password"],
            new_password=serializer.validated_data["new_password"],
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response(status=status.HTTP_204_NO_CONTENT)
