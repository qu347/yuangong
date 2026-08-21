from django.db import connection
from drf_spectacular.utils import OpenApiResponse, extend_schema
from rest_framework import status
from rest_framework.permissions import BasePermission
from rest_framework.response import Response
from rest_framework.views import APIView

from .pagination import SearchPagination
from .search import search_directory
from .serializers import (
    DashboardSummarySerializer,
    HrStatisticsSerializer,
    SearchQuerySerializer,
    SearchResultSerializer,
)
from .services import dashboard_summary, hr_statistics


class HealthView(APIView):
    authentication_classes = []
    permission_classes = []

    @extend_schema(
        summary="服务健康检查",
        responses={
            200: OpenApiResponse(description="服务与数据库正常"),
            503: OpenApiResponse(description="数据库不可用"),
        },
    )
    def get(self, request):
        del request
        payload = {
            "status": "ok",
            "service": "employee-api",
            "version": "0.1.0",
            "database": "ok",
        }

        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                cursor.fetchone()
        except Exception:  # noqa: BLE001 - health endpoint intentionally hides database details
            payload.update(status="unavailable", database="unavailable")
            return Response(payload, status=status.HTTP_503_SERVICE_UNAVAILABLE)

        return Response(payload, status=status.HTTP_200_OK)


class CanViewHrStatistics(BasePermission):
    message = "当前账号没有查看 HR 统计的权限。"

    def has_permission(self, request, view):
        del view
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.has_perm("audit.view_auditevent")
        )


class DashboardSummaryView(APIView):
    @extend_schema(responses=DashboardSummarySerializer)
    def get(self, request):
        return Response(DashboardSummarySerializer(dashboard_summary(request.user)).data)


class HrStatisticsView(APIView):
    permission_classes = [CanViewHrStatistics]

    @extend_schema(responses=HrStatisticsSerializer)
    def get(self, request):
        return Response(HrStatisticsSerializer(hr_statistics()).data)


class GlobalSearchView(APIView):
    pagination_class = SearchPagination

    @extend_schema(parameters=[SearchQuerySerializer], responses=SearchResultSerializer(many=True))
    def get(self, request):
        query_serializer = SearchQuerySerializer(data=request.query_params)
        query_serializer.is_valid(raise_exception=True)
        results = search_directory(query_serializer.validated_data["q"])
        paginator = self.pagination_class()
        page = paginator.paginate_queryset(results, request, view=self)
        return paginator.get_paginated_response(SearchResultSerializer(page, many=True).data)
