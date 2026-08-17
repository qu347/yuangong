from django.urls import path

from .views import EmployeeDepartView, EmployeeDetailView, EmployeeListView, EmployeeReactivateView

app_name = "employees"

urlpatterns = [
    path("employees/", EmployeeListView.as_view(), name="employee-list"),
    path("employees/<uuid:id>/", EmployeeDetailView.as_view(), name="employee-detail"),
    path("employees/<uuid:id>/depart/", EmployeeDepartView.as_view(), name="employee-depart"),
    path(
        "employees/<uuid:id>/reactivate/",
        EmployeeReactivateView.as_view(),
        name="employee-reactivate",
    ),
]
