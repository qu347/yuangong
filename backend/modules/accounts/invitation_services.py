from django.conf import settings
from django.contrib.auth.models import Group
from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from modules.audit.services import record_audit_event
from modules.common.exceptions import BusinessConflict
from modules.employees.models import Employee

from .models import AccountInvitation, User, normalize_account_email
from .notifications import AccountNotificationService
from .password_validation import validate_account_password
from .security_tokens import digest_one_time_token, generate_one_time_token

INVITATION_PURPOSE = "account_invitation"


def _invalid_invitation():
    return ValidationError({"token": "邀请码无效或已失效。"})


def _validate_target(employee, *, username, email, target_role):
    if employee.employment_status != Employee.EmploymentStatus.ACTIVE:
        raise BusinessConflict("离职员工不能创建账号邀请。", code="invalid_state_transition")
    if employee.user_id is not None:
        raise BusinessConflict("员工已经关联登录账号。", code="resource_in_use")
    if target_role not in AccountInvitation.TargetRole.values:
        raise ValidationError({"target_role": "只允许 employee 或 hr_admin。"})
    if not username or User.objects.filter(username=username).exists():
        raise BusinessConflict("登录名已存在。", code="uniqueness_conflict")
    if not email:
        raise ValidationError({"email": "必须提供账号邮箱。"})
    if User.objects.filter(email__iexact=email).exists():
        raise BusinessConflict("账号邮箱已存在。", code="uniqueness_conflict")
    open_invitations = AccountInvitation.objects.filter(accepted_at=None, revoked_at=None)
    if open_invitations.filter(username=username).exists():
        raise BusinessConflict("登录名已有有效邀请。", code="resource_in_use")
    if open_invitations.filter(email__iexact=email).exists():
        raise BusinessConflict("账号邮箱已有有效邀请。", code="resource_in_use")


def create_invitation(
    *,
    actor,
    employee_id,
    username,
    email=None,
    target_role,
    notification_service=None,
    request_id=None,
):
    notification_service = notification_service or AccountNotificationService()
    now = timezone.now()
    with transaction.atomic():
        employee = Employee.objects.select_for_update().get(pk=employee_id)
        normalized_username = username.strip()
        normalized_email = normalize_account_email(email or employee.work_email)
        AccountInvitation.objects.filter(
            employee=employee,
            accepted_at=None,
            revoked_at=None,
            expires_at__lte=now,
        ).update(revoked_at=now)
        if AccountInvitation.objects.filter(
            employee=employee, accepted_at=None, revoked_at=None
        ).exists():
            raise BusinessConflict("该员工已有有效邀请。", code="resource_in_use")
        _validate_target(
            employee,
            username=normalized_username,
            email=normalized_email,
            target_role=target_role,
        )
        raw_token, digest = generate_one_time_token(INVITATION_PURPOSE)
        expires_at = now + settings.ACCOUNT_INVITATION_TTL
        try:
            invitation = AccountInvitation.objects.create(
                employee=employee,
                email=normalized_email,
                username=normalized_username,
                target_role=target_role,
                token_digest=digest,
                expires_at=expires_at,
                created_by=actor,
                last_sent_at=now,
            )
        except IntegrityError as error:
            raise BusinessConflict(
                "邀请与现有账号状态冲突。", code="uniqueness_conflict"
            ) from error
        record_audit_event(
            actor=actor,
            action="account_invitation_created",
            resource_type="account_invitation",
            resource_id=invitation.id,
            resource_label=invitation.username,
            changes={
                "username": {"to": invitation.username},
                "email": {"to": invitation.email},
                "target_role": {"to": invitation.target_role},
            },
            source="api",
            request_id=request_id,
        )
        notification_service.send_invitation(
            email=normalized_email, token=raw_token, expires_at=expires_at
        )
        return invitation


def resend_invitation(*, invitation_id, actor, notification_service=None, request_id=None):
    notification_service = notification_service or AccountNotificationService()
    now = timezone.now()
    with transaction.atomic():
        invitation = AccountInvitation.objects.select_for_update().get(pk=invitation_id)
        if invitation.accepted_at is not None or invitation.revoked_at is not None:
            raise BusinessConflict("邀请已结束，不能重发。", code="invalid_state_transition")
        raw_token, digest = generate_one_time_token(INVITATION_PURPOSE)
        invitation.token_digest = digest
        invitation.expires_at = now + settings.ACCOUNT_INVITATION_TTL
        invitation.send_count += 1
        invitation.last_sent_at = now
        invitation.save(
            update_fields=["token_digest", "expires_at", "send_count", "last_sent_at", "updated_at"]
        )
        record_audit_event(
            actor=actor,
            action="account_invitation_resent",
            resource_type="account_invitation",
            resource_id=invitation.id,
            resource_label=invitation.username,
            changes={"send_count": {"to": invitation.send_count}},
            source="api",
            request_id=request_id,
        )
        notification_service.send_invitation(
            email=invitation.email, token=raw_token, expires_at=invitation.expires_at
        )
        return invitation


def revoke_invitation(*, invitation_id, actor, request_id=None):
    with transaction.atomic():
        invitation = AccountInvitation.objects.select_for_update().get(pk=invitation_id)
        if invitation.accepted_at is not None:
            raise BusinessConflict("已接受邀请不能撤销。", code="invalid_state_transition")
        if invitation.revoked_at is not None:
            return invitation, False
        invitation.revoked_at = timezone.now()
        invitation.save(update_fields=["revoked_at", "updated_at"])
        record_audit_event(
            actor=actor,
            action="account_invitation_revoked",
            resource_type="account_invitation",
            resource_id=invitation.id,
            resource_label=invitation.username,
            changes={"status": {"from": "pending", "to": "revoked"}},
            source="api",
            request_id=request_id,
        )
        return invitation, True


def accept_invitation(*, raw_token, new_password, request_id=None):
    digest = digest_one_time_token(INVITATION_PURPOSE, raw_token.strip())
    now = timezone.now()
    with transaction.atomic():
        invitation = (
            AccountInvitation.objects.select_for_update()
            .select_related("employee")
            .filter(token_digest=digest)
            .first()
        )
        if (
            invitation is None
            or invitation.accepted_at is not None
            or invitation.revoked_at is not None
            or invitation.expires_at <= now
        ):
            raise _invalid_invitation()
        employee = Employee.objects.select_for_update().get(pk=invitation.employee_id)
        if employee.employment_status != Employee.EmploymentStatus.ACTIVE or employee.user_id:
            raise _invalid_invitation()
        if (
            User.objects.filter(username=invitation.username).exists()
            or User.objects.filter(email__iexact=invitation.email).exists()
        ):
            raise _invalid_invitation()
        user = User(username=invitation.username, email=invitation.email, is_active=True)
        validate_account_password(new_password, user=user, employee=employee)
        user.set_password(new_password)
        user.save()
        user.groups.set([Group.objects.get(name=invitation.target_role)])
        employee.user = user
        employee.save(update_fields=["user", "updated_at"])
        invitation.accepted_at = now
        invitation.save(update_fields=["accepted_at", "updated_at"])
        record_audit_event(
            actor=user,
            action="account_invitation_accepted",
            resource_type="user",
            resource_id=user.id,
            resource_label=user.username,
            changes={"username": {"to": user.username}, "role": {"to": invitation.target_role}},
            source="api",
            request_id=request_id,
        )
        return user
