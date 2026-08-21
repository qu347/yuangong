from django.http import Http404
from django.shortcuts import get_object_or_404
from rest_framework.exceptions import PermissionDenied

from modules.accounts.rbac import ROLE_SYSTEM_ADMIN

from ..models import Employee
from .models import EmployeeAttachment


def is_system_admin(user):
    return bool(
        user
        and user.is_authenticated
        and (user.is_superuser or user.groups.filter(name=ROLE_SYSTEM_ADMIN).exists())
    )


def visible_attachments(user):
    base = EmployeeAttachment.objects.filter(deleted_at__isnull=True).select_related(
        "employee",
        "employee__user",
        "uploaded_by",
    )
    if is_system_admin(user):
        return base
    _require_attachment_view(user)
    if _can_manage_attachments(user):
        return _exclude_system_admin_targets(base)
    employee_id = getattr(getattr(user, "employee_profile", None), "id", None)
    return base.filter(employee_id=employee_id) if employee_id else base.none()


def get_visible_employee(user, employee_id, *, manage=False):
    base = Employee.objects.select_related("user")
    if is_system_admin(user):
        return get_object_or_404(base, pk=employee_id)

    if manage:
        if not (
            user.has_perm("employees.add_employeeattachment")
            or user.has_perm("employees.change_employeeattachment")
        ):
            raise PermissionDenied("当前账号没有管理员工附件的权限。")
        return get_object_or_404(_exclude_system_admin_targets(base), pk=employee_id)

    _require_attachment_view(user)
    if _can_manage_attachments(user):
        return get_object_or_404(_exclude_system_admin_targets(base), pk=employee_id)

    employee_id_for_user = getattr(
        getattr(user, "employee_profile", None),
        "id",
        None,
    )
    if employee_id_for_user is None or str(employee_id_for_user) != str(employee_id):
        raise Http404
    return get_object_or_404(base, pk=employee_id_for_user)


def manageable_attachments(user):
    base = EmployeeAttachment.objects.filter(deleted_at__isnull=True).select_related(
        "employee",
        "employee__user",
        "uploaded_by",
    )
    if is_system_admin(user):
        return base
    if not _can_manage_attachments(user):
        raise PermissionDenied("当前账号没有管理员工附件的权限。")
    return _exclude_system_admin_targets(base)


def _require_attachment_view(user):
    if not user.has_perm("employees.view_employeeattachment"):
        raise PermissionDenied("当前账号没有查看员工附件的权限。")


def _can_manage_attachments(user):
    return user.has_perm("employees.add_employeeattachment") or user.has_perm(
        "employees.change_employeeattachment"
    )


def _exclude_system_admin_targets(queryset):
    return (
        queryset.exclude(employee__user__groups__name=ROLE_SYSTEM_ADMIN)
        .exclude(employee__user__is_superuser=True)
        .distinct()
        if queryset.model is EmployeeAttachment
        else queryset.exclude(user__groups__name=ROLE_SYSTEM_ADMIN)
        .exclude(user__is_superuser=True)
        .distinct()
    )
