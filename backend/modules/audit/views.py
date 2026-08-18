from django.utils.dateparse import parse_datetime
from rest_framework.exceptions import ValidationError
from rest_framework.generics import ListAPIView, RetrieveAPIView
from rest_framework.permissions import BasePermission

from modules.common.pagination import DirectoryPagination

from .models import AuditEvent
from .serializers import AuditEventSerializer


class CanViewAudit(BasePermission):
    message = "当前账号没有查看审计事件的权限。"

    def has_permission(self, request, view):
        del view
        return bool(request.user and request.user.has_perm("audit.view_auditevent"))


class AuditEventListView(ListAPIView):
    serializer_class = AuditEventSerializer
    permission_classes = [CanViewAudit]
    pagination_class = DirectoryPagination

    def get_queryset(self):
        queryset = AuditEvent.objects.select_related("actor")
        exact_filters = {
            "actor_id": self.request.query_params.get("actor"),
            "action": self.request.query_params.get("action"),
            "resource_type": self.request.query_params.get("resource_type"),
            "resource_id": self.request.query_params.get("resource_id"),
            "source": self.request.query_params.get("source"),
        }
        queryset = queryset.filter(**{key: value for key, value in exact_filters.items() if value})
        for parameter, lookup in (
            ("created_after", "created_at__gte"),
            ("created_before", "created_at__lte"),
        ):
            raw_value = self.request.query_params.get(parameter)
            if raw_value:
                parsed_value = parse_datetime(raw_value)
                if parsed_value is None:
                    raise ValidationError({parameter: "必须是 ISO 8601 日期时间。"})
                queryset = queryset.filter(**{lookup: parsed_value})
        ordering = self.request.query_params.get("ordering", "-created_at")
        if ordering not in {"created_at", "-created_at", "action", "-action"}:
            raise ValidationError({"ordering": "不支持该排序字段。"})
        return queryset.order_by(ordering, "-id")


class AuditEventDetailView(RetrieveAPIView):
    serializer_class = AuditEventSerializer
    permission_classes = [CanViewAudit]
    queryset = AuditEvent.objects.select_related("actor")
