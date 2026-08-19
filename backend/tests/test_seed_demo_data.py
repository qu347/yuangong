from io import StringIO

import pytest
from django.contrib.auth.models import Group
from django.core.management import call_command
from django.core.management.base import CommandError

from modules.accounts.models import User
from modules.employees.models import Employee
from modules.organizations.models import Department, Position


@pytest.mark.django_db
def test_seed_demo_data_is_idempotent_and_uses_only_fictional_directory_data(monkeypatch):
    password = "test-only-seed-password-5931"
    monkeypatch.setenv("EMPLOYEE_DEMO_PASSWORD", password)
    first_output = StringIO()
    second_output = StringIO()

    call_command("seed_demo_data", stdout=first_output)
    first_counts = (
        Department.objects.count(),
        Position.objects.count(),
        Employee.objects.count(),
        User.objects.filter(username="demo.employee").count(),
    )
    call_command("seed_demo_data", stdout=second_output)

    assert first_counts == (4, 6, 12, 1)
    assert (
        Department.objects.count(),
        Position.objects.count(),
        Employee.objects.count(),
        User.objects.filter(username="demo.employee").count(),
    ) == first_counts
    assert Group.objects.filter(name__in=("system_admin", "hr_admin", "employee")).count() == 3
    assert set(
        Group.objects.get(name="employee").permissions.values_list(
            "content_type__app_label", "codename"
        )
    ) == {
        ("employees", "view_employee"),
        ("organizations", "view_department"),
        ("organizations", "view_position"),
    }
    expected_management_permissions = {
        ("audit", "view_auditevent"),
        ("employees", "add_employee"),
        ("employees", "change_employee"),
        ("employees", "view_employee"),
        ("organizations", "add_department"),
        ("organizations", "change_department"),
        ("organizations", "view_department"),
        ("organizations", "add_position"),
        ("organizations", "change_position"),
        ("organizations", "view_position"),
    }
    expected_system_permissions = expected_management_permissions | {
        ("accounts", "view_user"),
        ("accounts", "change_user"),
        ("accounts", "add_accountinvitation"),
        ("accounts", "view_accountinvitation"),
        ("accounts", "change_accountinvitation"),
        ("audit", "export_auditevent"),
    }
    assert (
        set(
            Group.objects.get(name="hr_admin").permissions.values_list(
                "content_type__app_label", "codename"
            )
        )
        == expected_management_permissions
    )
    assert (
        set(
            Group.objects.get(name="system_admin").permissions.values_list(
                "content_type__app_label", "codename"
            )
        )
        == expected_system_permissions
    )
    assert all(
        employee.work_email.endswith("@example.test")
        for employee in Employee.objects.exclude(work_email="")
    )
    assert all(
        not employee.work_phone or employee.work_phone.startswith("010-5550-")
        for employee in Employee.objects.all()
    )
    user = User.objects.get(username="demo.employee")
    assert user.check_password(password)
    assert user.employee_profile.employee_no == "EMP-0001"
    assert list(user.groups.values_list("name", flat=True)) == ["employee"]
    assert password not in first_output.getvalue()
    assert password not in second_output.getvalue()


@pytest.mark.django_db
def test_seed_demo_data_requires_a_process_password(monkeypatch):
    monkeypatch.delenv("EMPLOYEE_DEMO_PASSWORD", raising=False)

    with pytest.raises(CommandError, match="EMPLOYEE_DEMO_PASSWORD"):
        call_command("seed_demo_data")

    assert Department.objects.count() == 0
    assert Employee.objects.count() == 0
