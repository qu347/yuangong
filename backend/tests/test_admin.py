import pytest
from django.contrib import admin

from modules.accounts.models import AccountInvitation, AccountSession, PasswordResetChallenge, User
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


@pytest.mark.django_db
def test_directory_admin_disables_delete_and_protects_employee_lifecycle_fields(rf):
    request = rf.get("/admin/")

    for model in (Department, Position, Employee):
        assert admin.site._registry[model].has_delete_permission(request) is False
    employee_admin = admin.site._registry[Employee]
    assert "employment_status" in employee_admin.get_readonly_fields(request)
    assert "user" in employee_admin.get_readonly_fields(request)


@pytest.mark.django_db
def test_department_admin_create_and_update_are_audited(rf):
    from modules.audit.models import AuditEvent

    actor = User.objects.create_superuser(username="admin_auditor")
    request = rf.post("/admin/organizations/department/add/")
    request.user = actor
    department_admin = admin.site._registry[Department]
    department = Department(code="ADMIN-AUDIT", name="后台审计部")

    department_admin.save_model(request, department, form=None, change=False)
    department.name = "后台审计更新部"
    department_admin.save_model(request, department, form=None, change=True)

    assert list(AuditEvent.objects.values_list("action", "source")) == [
        ("update", "admin"),
        ("create", "admin"),
    ]
    assert AuditEvent.objects.get(action="update").changes == {
        "name": {"from": "后台审计部", "to": "后台审计更新部"}
    }


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("model", "forbidden_fields"),
    [
        (AccountInvitation, {"token_digest"}),
        (PasswordResetChallenge, {"token_digest"}),
        (AccountSession, {"current_refresh_jti"}),
    ],
)
def test_account_security_admin_is_read_only_and_hides_sensitive_identifiers(
    rf,
    model,
    forbidden_fields,
):
    assert admin.site.is_registered(model)
    model_admin = admin.site._registry[model]
    request = rf.get("/admin/accounts/")

    assert model_admin.has_add_permission(request) is False
    assert model_admin.has_change_permission(request) is False
    assert model_admin.has_delete_permission(request) is False
    assert forbidden_fields.isdisjoint(model_admin.get_fields(request))
