from drf_spectacular.utils import extend_schema
from rest_framework import generics, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from .invitation_serializers import (
    AccountInvitationCreateSerializer,
    AccountInvitationSerializer,
    InvitationAcceptSerializer,
    InvitationActionResponseSerializer,
)
from .invitation_services import (
    accept_invitation,
    create_invitation,
    resend_invitation,
    revoke_invitation,
)
from .models import AccountInvitation
from .permissions import CanManageAccounts
from .throttles import InvitationAcceptRateThrottle


class InvitationListCreateView(generics.ListCreateAPIView):
    permission_classes = [CanManageAccounts]
    queryset = AccountInvitation.objects.select_related("employee", "created_by")

    def get_serializer_class(self):
        return (
            AccountInvitationSerializer
            if self.request.method == "GET"
            else AccountInvitationCreateSerializer
        )

    def post(self, request, *args, **kwargs):
        del args, kwargs
        serializer = AccountInvitationCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        invitation = create_invitation(
            actor=request.user,
            request_id=request.headers.get("X-Request-ID"),
            **serializer.validated_data,
        )
        return Response(
            AccountInvitationSerializer(invitation).data,
            status=status.HTTP_201_CREATED,
        )


class InvitationDetailView(generics.RetrieveAPIView):
    permission_classes = [CanManageAccounts]
    serializer_class = AccountInvitationSerializer
    queryset = AccountInvitation.objects.select_related("employee", "created_by")
    lookup_url_kwarg = "invitation_id"


class InvitationResendView(APIView):
    permission_classes = [CanManageAccounts]

    @extend_schema(request=None, responses=AccountInvitationSerializer)
    def post(self, request, invitation_id):
        invitation = resend_invitation(
            invitation_id=invitation_id,
            actor=request.user,
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response(AccountInvitationSerializer(invitation).data)


class InvitationRevokeView(APIView):
    permission_classes = [CanManageAccounts]

    @extend_schema(request=None, responses=InvitationActionResponseSerializer)
    def post(self, request, invitation_id):
        _, changed = revoke_invitation(
            invitation_id=invitation_id,
            actor=request.user,
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response({"changed": changed})


class InvitationAcceptView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [InvitationAcceptRateThrottle]

    @extend_schema(request=InvitationAcceptSerializer, responses={204: None})
    def post(self, request):
        serializer = InvitationAcceptSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        accept_invitation(
            raw_token=serializer.validated_data["token"],
            new_password=serializer.validated_data["new_password"],
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response(status=status.HTTP_204_NO_CONTENT)
