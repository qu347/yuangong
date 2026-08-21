from django.urls import path

from .views import EmployeeAttachmentListCreateView

app_name = "employee_attachments"

urlpatterns = [
    path("", EmployeeAttachmentListCreateView.as_view(), name="list-create"),
]
