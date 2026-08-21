from django.urls import include, path

from .attachments.views import EmployeeAttachmentDetailView, EmployeeAttachmentDownloadView
from .views import EmployeeDepartView, EmployeeDetailView, EmployeeListView, EmployeeReactivateView

app_name = "employees"

urlpatterns = [
    path(
        "attachments/<uuid:attachment_id>/download/",
        EmployeeAttachmentDownloadView.as_view(),
        name="employee-attachment-download",
    ),
    path(
        "attachments/<uuid:attachment_id>/",
        EmployeeAttachmentDetailView.as_view(),
        name="employee-attachment-detail",
    ),
    path("employees/", EmployeeListView.as_view(), name="employee-list"),
    path(
        "employees/<uuid:employee_id>/attachments/",
        include("modules.employees.attachments.urls"),
    ),
    path("employees/<uuid:id>/", EmployeeDetailView.as_view(), name="employee-detail"),
    path("employees/<uuid:id>/depart/", EmployeeDepartView.as_view(), name="employee-depart"),
    path(
        "employees/<uuid:id>/reactivate/",
        EmployeeReactivateView.as_view(),
        name="employee-reactivate",
    ),
]
