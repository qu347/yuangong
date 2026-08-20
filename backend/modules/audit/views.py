from django.conf import settings
from django.http import HttpResponse
from django.utils import timezone
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework.generics import ListAPIView, RetrieveAPIView
from rest_framework.permissions import BasePermission
from rest_framework.views import APIView

from modules.common.exceptions import ExportTooLarge
from modules.common.pagination import DirectoryPagination

from .export import build_audit_csv
from .filters import apply_audit_filters
from .models import AuditEvent
from .serializers import AuditEventSerializer
from .services import record_audit_event

AUDIT_FILTER_PARAMETERS = [
    OpenApiParameter("actor", str),
    OpenApiParameter("action", str),
    OpenApiParameter("resource_type", str),
    OpenApiParameter("resource_id", str),
    OpenApiParameter("source", str),
    OpenApiParameter("created_after", OpenApiTypes.DATETIME),
    OpenApiParameter("created_before", OpenApiTypes.DATETIME),
    OpenApiParameter("ordering", str, enum=["created_at", "-created_at", "action", "-action"]),
]


class CanViewAudit(BasePermission):
    message = "当前账号没有查看审计事件的权限。"

    def has_permission(self, request, view):
        del view
        return bool(request.user and request.user.has_perm("audit.view_auditevent"))


class CanExportAudit(BasePermission):
    message = "当前账号没有导出审计事件的权限。"

    def has_permission(self, request, view):
        del view
        return bool(request.user and request.user.has_perm("audit.export_auditevent"))


class AuditEventListView(ListAPIView):
    serializer_class = AuditEventSerializer
    permission_classes = [CanViewAudit]
    pagination_class = DirectoryPagination

    def get_queryset(self):
        queryset, _ = apply_audit_filters(
            AuditEvent.objects.select_related("actor"), self.request.query_params
        )
        return queryset


class AuditEventExportView(APIView):
    permission_classes = [CanExportAudit]

    @extend_schema(
        parameters=AUDIT_FILTER_PARAMETERS,
        responses={(200, "text/csv"): OpenApiTypes.BINARY},
    )
    def get(self, request):
        queryset, filter_summary = apply_audit_filters(
            AuditEvent.objects.select_related("actor"), request.query_params
        )
        limit = settings.AUDIT_EXPORT_MAX_ROWS
        events = list(queryset[: limit + 1])
        if len(events) > limit:
            raise ExportTooLarge(count=len(events), limit=limit)

        content = build_audit_csv(events)
        record_audit_event(
            actor=request.user,
            action=AuditEvent.Action.AUDIT_EXPORTED,
            resource_type="audit_event",
            resource_id="export",
            resource_label="审计 CSV 导出",
            changes={
                "filters": filter_summary,
                "row_count": len(events),
                "format": "csv",
            },
            source=AuditEvent.Source.API,
            request_id=request.headers.get("X-Request-ID"),
        )
        timestamp = timezone.now().strftime("%Y%m%dT%H%M%SZ")
        response = HttpResponse(content, content_type="text/csv; charset=utf-8")
        response["Content-Disposition"] = f'attachment; filename="audit-events-{timestamp}.csv"'
        return response


class AuditEventDetailView(RetrieveAPIView):
    serializer_class = AuditEventSerializer
    permission_classes = [CanViewAudit]
    queryset = AuditEvent.objects.select_related("actor")
