from uuid import UUID

from drf_spectacular.utils import OpenApiParameter, extend_schema, extend_schema_view
from rest_framework import filters, generics
from rest_framework.exceptions import ValidationError

from modules.common.pagination import DirectoryPagination

from .models import Employee
from .serializers import EmployeeSerializer


@extend_schema_view(
    get=extend_schema(
        parameters=[
            OpenApiParameter(
                name="department",
                type={"type": "string", "format": "uuid"},
                description="部门 UUID",
            ),
            OpenApiParameter(
                name="status",
                type=str,
                enum=[choice.value for choice in Employee.EmploymentStatus],
                description="在职状态",
            ),
        ]
    )
)
class EmployeeListView(generics.ListAPIView):
    serializer_class = EmployeeSerializer
    pagination_class = DirectoryPagination
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ["full_name", "employee_no", "work_email"]
    ordering_fields = ["employee_no", "full_name", "hire_date", "created_at"]
    ordering = ["employee_no"]

    def get_queryset(self):
        queryset = Employee.objects.select_related("department", "position").all()
        department = self.request.query_params.get("department")
        if department:
            try:
                department_id = UUID(department)
            except ValueError as error:
                raise ValidationError({"department": "department 必须是有效的 UUID。"}) from error
            queryset = queryset.filter(department_id=department_id)

        status = self.request.query_params.get("status")
        if status:
            valid_statuses = {choice.value for choice in Employee.EmploymentStatus}
            if status not in valid_statuses:
                raise ValidationError({"status": "status 必须是 active 或 departed。"})
            queryset = queryset.filter(employment_status=status)
        return queryset


class EmployeeDetailView(generics.RetrieveAPIView):
    queryset = Employee.objects.select_related("department", "position").all()
    serializer_class = EmployeeSerializer
    lookup_url_kwarg = "id"
