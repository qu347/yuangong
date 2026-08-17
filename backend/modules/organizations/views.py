from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView

from modules.common.permissions import DirectoryModelPermission

from .models import Department, Position
from .serializers import (
    DepartmentSerializer,
    DepartmentWriteSerializer,
    PositionSerializer,
    PositionWriteSerializer,
)
from .services import (
    create_department,
    create_position,
    set_department_active,
    set_position_active,
    update_department,
    update_position,
)


class DepartmentListView(generics.ListCreateAPIView):
    queryset = Department.objects.select_related("parent").all()
    serializer_class = DepartmentSerializer
    pagination_class = None
    permission_classes = [DirectoryModelPermission]
    permission_model = Department

    def get_serializer_class(self):
        return DepartmentSerializer if self.request.method == "GET" else DepartmentWriteSerializer

    def post(self, request, *args, **kwargs):
        del args, kwargs
        serializer = DepartmentWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        department = create_department(
            actor=request.user,
            data=serializer.validated_data,
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response(DepartmentSerializer(department).data, status=status.HTTP_201_CREATED)


class DepartmentDetailView(generics.RetrieveUpdateAPIView):
    queryset = Department.objects.select_related("parent").all()
    serializer_class = DepartmentSerializer
    lookup_url_kwarg = "id"
    permission_classes = [DirectoryModelPermission]
    permission_model = Department

    def get_serializer_class(self):
        return DepartmentSerializer if self.request.method == "GET" else DepartmentWriteSerializer

    def patch(self, request, *args, **kwargs):
        del args, kwargs
        department = self.get_object()
        serializer = DepartmentWriteSerializer(department, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        department = update_department(
            department_id=department.pk,
            actor=request.user,
            data=serializer.validated_data,
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response(DepartmentSerializer(department).data)


class PositionListView(generics.ListCreateAPIView):
    queryset = Position.objects.select_related("department").order_by(
        "department__sort_order",
        "name",
        "code",
    )
    serializer_class = PositionSerializer
    pagination_class = None
    permission_classes = [DirectoryModelPermission]
    permission_model = Position

    def get_serializer_class(self):
        return PositionSerializer if self.request.method == "GET" else PositionWriteSerializer

    def post(self, request, *args, **kwargs):
        del args, kwargs
        serializer = PositionWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        position = create_position(
            actor=request.user,
            data=serializer.validated_data,
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response(PositionSerializer(position).data, status=status.HTTP_201_CREATED)


class PositionDetailView(generics.RetrieveUpdateAPIView):
    queryset = Position.objects.select_related("department")
    lookup_url_kwarg = "id"
    permission_classes = [DirectoryModelPermission]
    permission_model = Position

    def get_serializer_class(self):
        return PositionSerializer if self.request.method == "GET" else PositionWriteSerializer

    def patch(self, request, *args, **kwargs):
        del args, kwargs
        position = self.get_object()
        serializer = PositionWriteSerializer(position, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        position = update_position(
            position_id=position.pk,
            actor=request.user,
            data=serializer.validated_data,
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response(PositionSerializer(position).data)


class DepartmentStatusView(APIView):
    permission_classes = [DirectoryModelPermission]
    permission_model = Department
    permission_action = "change"
    active = True

    def post(self, request, id):
        department, changed = set_department_active(
            department_id=id,
            active=self.active,
            actor=request.user,
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response({"department": DepartmentSerializer(department).data, "changed": changed})


class DepartmentActivateView(DepartmentStatusView):
    active = True


class DepartmentDeactivateView(DepartmentStatusView):
    active = False


class PositionStatusView(APIView):
    permission_classes = [DirectoryModelPermission]
    permission_model = Position
    permission_action = "change"
    active = True

    def post(self, request, id):
        position, changed = set_position_active(
            position_id=id,
            active=self.active,
            actor=request.user,
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response({"position": PositionSerializer(position).data, "changed": changed})


class PositionActivateView(PositionStatusView):
    active = True


class PositionDeactivateView(PositionStatusView):
    active = False
