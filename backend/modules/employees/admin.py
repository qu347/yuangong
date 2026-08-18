from django.contrib import admin

from .models import Employee


@admin.register(Employee)
class EmployeeAdmin(admin.ModelAdmin):
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
