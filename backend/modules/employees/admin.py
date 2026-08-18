from django.contrib import admin

from modules.audit.admin_mixins import AuditedDirectoryAdminMixin

from .models import Employee


@admin.register(Employee)
class EmployeeAdmin(AuditedDirectoryAdminMixin, admin.ModelAdmin):
    audit_resource_type = "employee"
    audit_fields = (
        "employee_no",
        "full_name",
        "work_email",
        "work_phone",
        "department",
        "position",
        "hire_date",
    )
    list_display = (
        "employee_no",
        "full_name",
        "department",
        "position",
        "employment_status",
    )
    list_filter = ("employment_status", "department")
    search_fields = ("employee_no", "full_name", "work_email")
    autocomplete_fields = ("department", "position", "user")
    ordering = ("employee_no",)
    readonly_fields = ("employment_status", "user")
