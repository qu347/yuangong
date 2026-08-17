from django.contrib import admin

from .models import Department, Position


@admin.register(Department)
class DepartmentAdmin(admin.ModelAdmin):
    list_display = ("code", "name", "parent", "status", "sort_order")
    list_filter = ("status",)
    search_fields = ("code", "name")
    ordering = ("sort_order", "code")


@admin.register(Position)
class PositionAdmin(admin.ModelAdmin):
    list_display = ("code", "name", "department", "status")
    list_filter = ("status", "department")
    search_fields = ("code", "name")
    autocomplete_fields = ("department",)
