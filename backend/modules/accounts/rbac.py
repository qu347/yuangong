from django.contrib.auth.models import Group, Permission
from django.db import transaction

ROLE_EMPLOYEE = "employee"
ROLE_HR_ADMIN = "hr_admin"
ROLE_SYSTEM_ADMIN = "system_admin"

EMPLOYEE_PERMISSION_KEYS = {
    ("employees", "view_employee"),
    ("employees", "view_employeeattachment"),
    ("organizations", "view_department"),
    ("organizations", "view_position"),
}

MANAGEMENT_PERMISSION_KEYS = EMPLOYEE_PERMISSION_KEYS | {
    ("audit", "view_auditevent"),
    ("employees", "add_employee"),
    ("employees", "change_employee"),
    ("employees", "add_employeeattachment"),
    ("employees", "change_employeeattachment"),
    ("organizations", "add_department"),
    ("organizations", "change_department"),
    ("organizations", "add_position"),
    ("organizations", "change_position"),
}

SYSTEM_ADMIN_PERMISSION_KEYS = MANAGEMENT_PERMISSION_KEYS | {
    ("accounts", "view_user"),
    ("accounts", "change_user"),
    ("accounts", "add_accountinvitation"),
    ("accounts", "view_accountinvitation"),
    ("accounts", "change_accountinvitation"),
    ("audit", "export_auditevent"),
}


def _permissions_for(keys):
    permissions = []
    for app_label, codename in sorted(keys):
        permissions.append(
            Permission.objects.get(
                content_type__app_label=app_label,
                codename=codename,
            )
        )
    return permissions


@transaction.atomic
def sync_rbac_permissions():
    role_permissions = {
        ROLE_EMPLOYEE: EMPLOYEE_PERMISSION_KEYS,
        ROLE_HR_ADMIN: MANAGEMENT_PERMISSION_KEYS,
        ROLE_SYSTEM_ADMIN: SYSTEM_ADMIN_PERMISSION_KEYS,
    }
    groups = {}
    for role, permission_keys in role_permissions.items():
        group, _ = Group.objects.get_or_create(name=role)
        group.permissions.add(*_permissions_for(permission_keys))
        groups[role] = group
    return groups
