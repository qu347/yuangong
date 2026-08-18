from django.db.models import Q
from drf_spectacular.utils import OpenApiParameter, extend_schema, extend_schema_view
from rest_framework import filters, generics
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from modules.common.pagination import DirectoryPagination

from .account_serializers import (
    AccountActionResponseSerializer,
    AccountRoleChangeSerializer,
    AccountSerializer,
    AccountSessionRevokeResponseSerializer,
    AccountUpdateSerializer,
)
from .account_services import (
    activate_account,
    change_account_role,
    deactivate_account,
    revoke_account_sessions,
    update_account_email,
)
from .models import User
from .permissions import CanManageAccounts


@extend_schema_view(
    get=extend_schema(
        parameters=[
            OpenApiParameter("is_active", bool),
            OpenApiParameter("role", str, enum=["employee", "hr_admin", "system_admin"]),
            OpenApiParameter("employee", str),
        ]
    )
)
class AccountListView(generics.ListAPIView):
    permission_classes = [CanManageAccounts]
    serializer_class = AccountSerializer
    pagination_class = DirectoryPagination
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = [
        "username",
        "email",
        "employee_profile__employee_no",
        "employee_profile__full_name",
    ]
    ordering_fields = ["username", "email", "is_active", "last_login", "date_joined"]
    ordering = ["username"]

    def get_queryset(self):
        queryset = User.objects.select_related("employee_profile").prefetch_related("groups")
        active = self.request.query_params.get("is_active")
        if active is not None:
            if active not in {"true", "false"}:
                raise ValidationError({"is_active": "必须是 true 或 false。"})
            queryset = queryset.filter(is_active=active == "true")
        role = self.request.query_params.get("role")
        if role:
            if role not in {"employee", "hr_admin", "system_admin"}:
                raise ValidationError({"role": "不支持该角色。"})
            queryset = queryset.filter(groups__name=role)
        employee = self.request.query_params.get("employee")
        if employee:
            queryset = queryset.filter(
                Q(employee_profile__id=employee) | Q(employee_profile__employee_no=employee)
            )
        return queryset.distinct()


class AccountDetailView(generics.RetrieveAPIView):
    permission_classes = [CanManageAccounts]
    serializer_class = AccountSerializer
    queryset = User.objects.select_related("employee_profile").prefetch_related("groups")
    lookup_url_kwarg = "account_id"

    @extend_schema(request=AccountUpdateSerializer, responses=AccountSerializer)
    def patch(self, request, account_id):
        serializer = AccountUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        account = update_account_email(
            user_id=account_id,
            email=serializer.validated_data["email"],
            actor=request.user,
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response(AccountSerializer(account).data)


class AccountLifecycleView(APIView):
    permission_classes = [CanManageAccounts]
    operation = None

    @extend_schema(request=None, responses=AccountActionResponseSerializer)
    def post(self, request, account_id):
        account, changed = self.operation(
            user_id=account_id,
            actor=request.user,
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response({"account": AccountSerializer(account).data, "changed": changed})


class AccountActivateView(AccountLifecycleView):
    operation = staticmethod(activate_account)


class AccountDeactivateView(AccountLifecycleView):
    operation = staticmethod(deactivate_account)


class AccountRoleChangeView(APIView):
    permission_classes = [CanManageAccounts]

    @extend_schema(request=AccountRoleChangeSerializer, responses=AccountActionResponseSerializer)
    def post(self, request, account_id):
        serializer = AccountRoleChangeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        account, changed = change_account_role(
            user_id=account_id,
            role=serializer.validated_data["role"],
            actor=request.user,
            request_id=request.headers.get("X-Request-ID"),
        )
        payload = dict(AccountSerializer(account).data)
        payload["changed"] = changed
        return Response(payload)


class AccountRevokeSessionsView(APIView):
    permission_classes = [CanManageAccounts]

    @extend_schema(request=None, responses=AccountSessionRevokeResponseSerializer)
    def post(self, request, account_id):
        revoked = revoke_account_sessions(
            user_id=account_id,
            actor=request.user,
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response({"revoked_sessions": revoked})
