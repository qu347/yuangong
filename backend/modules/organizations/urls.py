from django.urls import path

from .views import (
    DepartmentActivateView,
    DepartmentDeactivateView,
    DepartmentDetailView,
    DepartmentListView,
    PositionActivateView,
    PositionDeactivateView,
    PositionDetailView,
    PositionListView,
)

app_name = "organizations"

urlpatterns = [
    path("departments/", DepartmentListView.as_view(), name="department-list"),
    path(
        "departments/<uuid:id>/",
        DepartmentDetailView.as_view(),
        name="department-detail",
    ),
    path(
        "departments/<uuid:id>/activate/",
        DepartmentActivateView.as_view(),
        name="department-activate",
    ),
    path(
        "departments/<uuid:id>/deactivate/",
        DepartmentDeactivateView.as_view(),
        name="department-deactivate",
    ),
    path("positions/", PositionListView.as_view(), name="position-list"),
    path("positions/<uuid:id>/", PositionDetailView.as_view(), name="position-detail"),
    path(
        "positions/<uuid:id>/activate/",
        PositionActivateView.as_view(),
        name="position-activate",
    ),
    path(
        "positions/<uuid:id>/deactivate/",
        PositionDeactivateView.as_view(),
        name="position-deactivate",
    ),
]
