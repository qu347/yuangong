from rest_framework import generics

from .models import Department, Position
from .serializers import DepartmentSerializer, PositionSerializer


class DepartmentListView(generics.ListAPIView):
    queryset = Department.objects.select_related("parent").all()
    serializer_class = DepartmentSerializer
    pagination_class = None


class DepartmentDetailView(generics.RetrieveAPIView):
    queryset = Department.objects.select_related("parent").all()
    serializer_class = DepartmentSerializer
    lookup_url_kwarg = "id"


class PositionListView(generics.ListAPIView):
    queryset = Position.objects.select_related("department").order_by(
        "department__sort_order",
        "name",
        "code",
    )
    serializer_class = PositionSerializer
    pagination_class = None
