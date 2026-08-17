import pytest
from django.contrib import admin

from modules.audit.models import AuditEvent
from modules.employees.models import Employee
from modules.organizations.models import Department, Position


@pytest.mark.django_db
def test_directory_models_are_registered_in_django_admin():
    assert admin.site.is_registered(Department)
    assert admin.site.is_registered(Position)
    assert admin.site.is_registered(Employee)


@pytest.mark.django_db
def test_audit_admin_is_registered_as_strictly_read_only(rf):
    assert admin.site.is_registered(AuditEvent)
    model_admin = admin.site._registry[AuditEvent]
    request = rf.get("/admin/audit/auditevent/")

    assert model_admin.has_add_permission(request) is False
    assert model_admin.has_change_permission(request) is False
    assert model_admin.has_delete_permission(request) is False
