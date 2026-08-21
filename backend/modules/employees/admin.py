from django.contrib import admin

from modules.audit.admin_mixins import AuditedDirectoryAdminMixin

from .models import Employee, EmployeeAttachment


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


@admin.register(EmployeeAttachment)
class EmployeeAttachmentAdmin(admin.ModelAdmin):
    list_display = ("original_filename", "employee", "file_type", "file_size", "created_at")
    list_filter = ("file_type", "deleted_at")
    search_fields = ("original_filename", "filename", "employee__employee_no")
    autocomplete_fields = ("employee", "uploaded_by")
    readonly_fields = (
        "id",
        "employee",
        "filename",
        "original_filename",
        "file_type",
        "file_size",
        "storage_path",
        "uploaded_by",
        "created_at",
        "updated_at",
        "deleted_at",
    )

    def has_add_permission(self, request):
        del request
        return False

    def has_change_permission(self, request, obj=None):
        del request, obj
        return False

    def has_delete_permission(self, request, obj=None):
        del request, obj
        return False
