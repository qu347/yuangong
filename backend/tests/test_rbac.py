from io import StringIO

import pytest
from django.contrib.auth.models import Group, Permission
from django.core.management import call_command


@pytest.mark.django_db
def test_sync_rbac_is_idempotent_and_preserves_extra_permissions():
    employee_group = Group.objects.create(name="employee")
    extra_permission = Permission.objects.get(
        content_type__app_label="accounts",
        codename="view_user",
    )
    employee_group.permissions.add(extra_permission)

    call_command("sync_rbac", stdout=StringIO())
    call_command("sync_rbac", stdout=StringIO())

    assert Group.objects.filter(name="employee").count() == 1
    assert Group.objects.filter(name="hr_admin").count() == 1
    assert Group.objects.filter(name="system_admin").count() == 1
    assert Group.objects.get(name="employee").permissions.filter(pk=extra_permission.pk).exists()
    assert set(
        Group.objects.get(name="employee").permissions.values_list(
            "content_type__app_label", "codename"
        )
    ) >= {
        ("accounts", "view_user"),
        ("employees", "view_employee"),
        ("organizations", "view_department"),
        ("organizations", "view_position"),
    }


@pytest.mark.django_db
def test_sync_rbac_grants_management_permissions_without_delete_permissions():
    call_command("sync_rbac", stdout=StringIO())

    for role in ("hr_admin", "system_admin"):
        permissions = set(
            Group.objects.get(name=role).permissions.values_list(
                "content_type__app_label", "codename"
            )
        )
        assert permissions >= {
            ("audit", "view_auditevent"),
            ("employees", "add_employee"),
            ("employees", "change_employee"),
            ("organizations", "add_department"),
            ("organizations", "change_department"),
            ("organizations", "add_position"),
            ("organizations", "change_position"),
        }
        assert not any(codename.startswith("delete_") for _, codename in permissions)

    hr_permissions = set(
        Group.objects.get(name="hr_admin").permissions.values_list(
            "content_type__app_label", "codename"
        )
    )
    system_permissions = set(
        Group.objects.get(name="system_admin").permissions.values_list(
            "content_type__app_label", "codename"
        )
    )
    assert ("audit", "export_auditevent") not in hr_permissions
    assert ("audit", "export_auditevent") in system_permissions
