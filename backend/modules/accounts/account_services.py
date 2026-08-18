from django.contrib.auth.models import Group
from django.db import IntegrityError, transaction
from rest_framework.exceptions import ValidationError

from modules.audit.services import record_audit_event
from modules.common.exceptions import BusinessConflict
from modules.employees.models import Employee

from .models import User, normalize_account_email
from .sessions import revoke_all_account_sessions
from .tokens import revoke_all_user_tokens

MANAGED_ROLES = {"employee", "hr_admin"}


def managed_role(user):
    roles = set(
        user.groups.filter(name__in=MANAGED_ROLES | {"system_admin"}).values_list("name", flat=True)
    )
    if "system_admin" in roles:
        return "system_admin"
    if "hr_admin" in roles:
        return "hr_admin"
    if "employee" in roles:
        return "employee"
    return None


def _ensure_business_target(user):
    if user.is_superuser or managed_role(user) == "system_admin":
        raise BusinessConflict(
            "超级用户和 system_admin 只能由 Django Admin 超级用户管理。",
            code="invalid_state_transition",
        )


def update_account_email(*, user_id, email, actor, request_id=None):
    normalized = normalize_account_email(email)
    if not normalized:
        raise ValidationError({"email": "账号邮箱不能为空。"})
    with transaction.atomic():
        user = User.objects.select_for_update().get(pk=user_id)
        _ensure_business_target(user)
        if User.objects.exclude(pk=user.pk).filter(email__iexact=normalized).exists():
            raise BusinessConflict("账号邮箱已存在。", code="uniqueness_conflict")
        before = user.email
        if before == normalized:
            return user
        user.email = normalized
        try:
            user.save(update_fields=["email", "updated_at"])
        except IntegrityError as error:
            raise BusinessConflict("账号邮箱已存在。", code="uniqueness_conflict") from error
        record_audit_event(
            actor=actor,
            action="update",
            resource_type="user",
            resource_id=user.id,
            resource_label=user.username,
            changes={"email": {"from": before, "to": normalized}},
            source="api",
            request_id=request_id,
        )
        return user


def deactivate_account(*, user_id, actor, request_id=None):
    with transaction.atomic():
        user = User.objects.select_for_update().get(pk=user_id)
        if user.pk == actor.pk:
            raise BusinessConflict("不能停用当前登录账号。", code="invalid_state_transition")
        _ensure_business_target(user)
        if not user.is_active:
            return user, False
        user.is_active = False
        user.save(update_fields=["is_active", "updated_at"])
        revoked = revoke_all_account_sessions(user, reason="account_deactivated")
        revoke_all_user_tokens(user)
        record_audit_event(
            actor=actor,
            action="account_deactivate",
            resource_type="user",
            resource_id=user.id,
            resource_label=user.username,
            changes={
                "is_active": {"from": True, "to": False},
                "revoked_sessions": {"to": revoked},
            },
            source="api",
            request_id=request_id,
        )
        return user, True


def activate_account(*, user_id, actor, request_id=None):
    with transaction.atomic():
        user = User.objects.select_for_update().get(pk=user_id)
        _ensure_business_target(user)
        if user.is_active:
            return user, False
        employee = getattr(user, "employee_profile", None)
        if employee is None or employee.employment_status != Employee.EmploymentStatus.ACTIVE:
            raise BusinessConflict("账号关联员工不是在职状态。", code="invalid_state_transition")
        if not user.email or managed_role(user) not in MANAGED_ROLES:
            raise BusinessConflict(
                "账号邮箱或角色不满足恢复条件。", code="invalid_state_transition"
            )
        user.is_active = True
        user.save(update_fields=["is_active", "updated_at"])
        record_audit_event(
            actor=actor,
            action="account_activated",
            resource_type="user",
            resource_id=user.id,
            resource_label=user.username,
            changes={"is_active": {"from": False, "to": True}},
            source="api",
            request_id=request_id,
        )
        return user, True


def change_account_role(*, user_id, role, actor, request_id=None):
    if role not in MANAGED_ROLES:
        raise ValidationError({"role": "只允许 employee 或 hr_admin。"})
    with transaction.atomic():
        user = User.objects.select_for_update().get(pk=user_id)
        _ensure_business_target(user)
        old_role = managed_role(user)
        if old_role == role:
            return user, False
        managed_groups = Group.objects.filter(name__in=MANAGED_ROLES)
        user.groups.remove(*managed_groups)
        user.groups.add(Group.objects.get(name=role))
        revoked = revoke_all_account_sessions(user, reason="role_changed")
        revoke_all_user_tokens(user)
        record_audit_event(
            actor=actor,
            action="account_role_changed",
            resource_type="user",
            resource_id=user.id,
            resource_label=user.username,
            changes={
                "role": {"from": old_role, "to": role},
                "revoked_sessions": {"to": revoked},
            },
            source="api",
            request_id=request_id,
        )
        return user, True


def revoke_account_sessions(*, user_id, actor, request_id=None):
    with transaction.atomic():
        user = User.objects.select_for_update().get(pk=user_id)
        _ensure_business_target(user)
        revoked = revoke_all_account_sessions(user, reason="admin_revoked")
        revoke_all_user_tokens(user)
        if revoked:
            record_audit_event(
                actor=actor,
                action="all_sessions_revoked",
                resource_type="user",
                resource_id=user.id,
                resource_label=user.username,
                changes={"revoked_sessions": {"to": revoked}},
                source="api",
                request_id=request_id,
            )
        return revoked
