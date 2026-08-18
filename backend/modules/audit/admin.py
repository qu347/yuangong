from django.contrib import admin

from .models import AuditEvent


@admin.register(AuditEvent)
class AuditEventAdmin(admin.ModelAdmin):
    list_display = ("created_at", "actor", "action", "resource_type", "resource_label", "source")
    list_filter = ("action", "resource_type", "source")
    search_fields = ("resource_id", "resource_label", "actor__username")
    readonly_fields = (
        "id",
        "actor",
        "action",
        "resource_type",
        "resource_id",
        "resource_label",
        "changes",
        "source",
        "request_id",
        "created_at",
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
