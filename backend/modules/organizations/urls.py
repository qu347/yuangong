from django.urls import path

from .views import DepartmentDetailView, DepartmentListView, PositionListView

app_name = "organizations"

urlpatterns = [
    path("departments/", DepartmentListView.as_view(), name="department-list"),
    path(
        "departments/<uuid:id>/",
        DepartmentDetailView.as_view(),
        name="department-detail",
    ),
    path("positions/", PositionListView.as_view(), name="position-list"),
]
