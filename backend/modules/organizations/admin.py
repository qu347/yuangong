from django.contrib import admin

from modules.audit.admin_mixins import AuditedDirectoryAdminMixin

from .models import Department, Position


@admin.register(Department)
class DepartmentAdmin(AuditedDirectoryAdminMixin, admin.ModelAdmin):
    audit_resource_type = "department"
    audit_fields = ("code", "name", "parent", "status", "sort_order")
    list_display = ("code", "name", "parent", "status", "sort_order")
    list_filter = ("status",)
    search_fields = ("code", "name")
    ordering = ("sort_order", "code")


@admin.register(Position)
class PositionAdmin(AuditedDirectoryAdminMixin, admin.ModelAdmin):
    audit_resource_type = "position"
    audit_fields = ("code", "name", "department", "status")
    list_display = ("code", "name", "department", "status")
    list_filter = ("status", "department")
    search_fields = ("code", "name")
    autocomplete_fields = ("department",)
