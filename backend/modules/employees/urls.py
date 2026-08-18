from django.urls import path

from .views import EmployeeDetailView, EmployeeListView

app_name = "employees"

urlpatterns = [
    path("employees/", EmployeeListView.as_view(), name="employee-list"),
    path("employees/<uuid:id>/", EmployeeDetailView.as_view(), name="employee-detail"),
]
