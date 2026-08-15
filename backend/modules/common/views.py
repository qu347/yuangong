from django.db import connection
from drf_spectacular.utils import OpenApiResponse, extend_schema
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView


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
