from django.conf import settings
from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from modules.audit.services import record_audit_event

from .models import PasswordResetChallenge, User
from .notifications import AccountNotificationService
from .password_validation import validate_account_password
from .security_tokens import digest_one_time_token, generate_one_time_token
from .sessions import revoke_all_account_sessions
from .throttles import consume_rate_limit
from .tokens import revoke_all_user_tokens

RESET_PURPOSE = "password_reset"


def _resolve_identifier(identifier):
    value = (identifier or "").strip()
    queryset = (
        User.objects.filter(email__iexact=value)
        if "@" in value
        else User.objects.filter(username=value)
    )
    return queryset.first() if queryset.count() == 1 else None


def request_password_reset(*, identifier, notification_service=None):
    if not consume_rate_limit(
        "password_reset",
        identifier,
        limit=settings.PASSWORD_RESET_REQUEST_LIMIT,
        window_seconds=3600,
    ):
        return False
    user = _resolve_identifier(identifier)
    if user is None or not user.is_active or not user.email:
        return False
    notification_service = notification_service or AccountNotificationService()
    now = timezone.now()
    with transaction.atomic():
        PasswordResetChallenge.objects.filter(user=user, used_at=None, revoked_at=None).update(
            revoked_at=now
        )
        raw_token, digest = generate_one_time_token(RESET_PURPOSE)
        challenge = PasswordResetChallenge.objects.create(
            user=user,
            token_digest=digest,
            expires_at=now + settings.PASSWORD_RESET_TTL,
            requested_from=PasswordResetChallenge.RequestedFrom.APP,
        )
        notification_service.send_password_reset(
            email=user.email, token=raw_token, expires_at=challenge.expires_at
        )
    return True


def confirm_password_reset(*, raw_token, new_password, request_id=None):
    digest = digest_one_time_token(RESET_PURPOSE, raw_token.strip())
    now = timezone.now()
    with transaction.atomic():
        challenge = (
            PasswordResetChallenge.objects.select_for_update()
            .select_related("user")
            .filter(token_digest=digest)
            .first()
        )
        if (
            challenge is None
            or challenge.used_at is not None
            or challenge.revoked_at is not None
            or challenge.expires_at <= now
        ):
            raise ValidationError({"token": "重置码无效或已失效。"})
        user = challenge.user
        if not user.is_active:
            raise ValidationError({"token": "重置码无效或已失效。"})
        employee = getattr(user, "employee_profile", None)
        validate_account_password(new_password, user=user, employee=employee)
        user.set_password(new_password)
        user.save(update_fields=["password", "updated_at"])
        challenge.used_at = now
        challenge.save(update_fields=["used_at"])
        revoke_all_account_sessions(user, reason="password_reset")
        revoke_all_user_tokens(user)
        record_audit_event(
            actor=user,
            action="password_reset_completed",
            resource_type="user",
            resource_id=user.id,
            resource_label=user.username,
            changes={},
            source="api",
            request_id=request_id,
        )


def change_password(*, user, current_password, new_password, request_id=None):
    if not user.check_password(current_password):
        raise ValidationError({"current_password": "当前密码不正确。"})
    employee = getattr(user, "employee_profile", None)
    validate_account_password(new_password, user=user, employee=employee)
    with transaction.atomic():
        locked = User.objects.select_for_update().get(pk=user.pk)
        locked.set_password(new_password)
        locked.save(update_fields=["password", "updated_at"])
        revoke_all_account_sessions(locked, reason="password_changed")
        revoke_all_user_tokens(locked)
        record_audit_event(
            actor=locked,
            action="password_changed",
            resource_type="user",
            resource_id=locked.id,
            resource_label=locked.username,
            changes={},
            source="api",
            request_id=request_id,
        )
