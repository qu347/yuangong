from uuid import UUID

from drf_spectacular.utils import OpenApiParameter, extend_schema, extend_schema_view
from rest_framework import filters, generics, status
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from modules.common.pagination import DirectoryPagination
from modules.common.permissions import DirectoryModelPermission

from .models import Employee
from .serializers import (
    EmployeeDetailSerializer,
    EmployeeSerializer,
    EmployeeStatusResponseSerializer,
    EmployeeWriteSerializer,
)
from .services import create_employee, depart_employee, reactivate_employee, update_employee


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
class EmployeeListView(generics.ListCreateAPIView):
    serializer_class = EmployeeSerializer
    pagination_class = DirectoryPagination
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ["full_name", "employee_no", "work_email"]
    ordering_fields = ["employee_no", "full_name", "hire_date", "created_at"]
    ordering = ["employee_no"]
    permission_classes = [DirectoryModelPermission]
    permission_model = Employee

    def get_serializer_class(self):
        return EmployeeSerializer if self.request.method == "GET" else EmployeeWriteSerializer

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

    def post(self, request, *args, **kwargs):
        del args, kwargs
        serializer = EmployeeWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        employee = create_employee(
            actor=request.user,
            data=serializer.validated_data,
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response(EmployeeDetailSerializer(employee).data, status=status.HTTP_201_CREATED)


class EmployeeDetailView(generics.RetrieveUpdateAPIView):
    queryset = Employee.objects.select_related("department", "position").all()
    lookup_url_kwarg = "id"
    permission_classes = [DirectoryModelPermission]
    permission_model = Employee

    def get_serializer_class(self):
        return EmployeeDetailSerializer if self.request.method == "GET" else EmployeeWriteSerializer

    def patch(self, request, *args, **kwargs):
        del args, kwargs
        employee = self.get_object()
        serializer = EmployeeWriteSerializer(employee, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        employee = update_employee(
            employee_id=employee.pk,
            actor=request.user,
            data=serializer.validated_data,
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response(EmployeeDetailSerializer(employee).data)


class EmployeeStatusView(APIView):
    permission_classes = [DirectoryModelPermission]
    permission_model = Employee
    permission_action = "change"
    operation = None

    @extend_schema(request=None, responses=EmployeeStatusResponseSerializer)
    def post(self, request, id):
        employee, changed = self.operation(
            employee_id=id,
            actor=request.user,
            request_id=request.headers.get("X-Request-ID"),
        )
        payload = {"employee": EmployeeDetailSerializer(employee).data, "changed": changed}
        if self.operation is reactivate_employee:
            payload["account_requires_activation"] = bool(
                employee.user_id and not employee.user.is_active
            )
        return Response(payload)


class EmployeeDepartView(EmployeeStatusView):
    operation = staticmethod(depart_employee)


class EmployeeReactivateView(EmployeeStatusView):
    operation = staticmethod(reactivate_employee)
