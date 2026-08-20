from django.core.exceptions import ValidationError

from .models import AuditEvent

SAFE_CHANGE_FIELDS = {
    "code",
    "name",
    "parent",
    "sort_order",
    "department",
    "position",
    "employee_no",
    "full_name",
    "work_email",
    "work_phone",
    "hire_date",
    "status",
    "employment_status",
    "is_active",
    "revoked_sessions",
    "session_id",
    "client_platform",
    "revoked_reason",
    "username",
    "email",
    "target_role",
    "role",
    "send_count",
    "filters",
    "row_count",
    "format",
}
SENSITIVE_KEY_FRAGMENTS = {
    "authorization",
    "credential",
    "password",
    "secret",
    "token",
    "jti",
    "database",
    "redis",
}


def _contains_sensitive_key(value):
    if isinstance(value, dict):
        for key, nested_value in value.items():
            normalized_key = str(key).lower()
            if any(fragment in normalized_key for fragment in SENSITIVE_KEY_FRAGMENTS):
                return True
            if _contains_sensitive_key(nested_value):
                return True
    elif isinstance(value, list):
        return any(_contains_sensitive_key(item) for item in value)
    return False


def record_audit_event(
    *,
    actor,
    action,
    resource_type,
    resource_id,
    resource_label,
    changes,
    source,
    request_id=None,
):
    if action not in AuditEvent.Action.values:
        raise ValidationError("未知的审计动作。")
    if source not in AuditEvent.Source.values:
        raise ValidationError("未知的审计来源。")
    if not isinstance(changes, dict):
        raise ValidationError("审计 changes 必须是对象。")
    if set(changes) - SAFE_CHANGE_FIELDS or _contains_sensitive_key(changes):
        raise ValidationError("审计内容包含未允许字段或敏感信息。")
    return AuditEvent.objects.create(
        actor=actor,
        action=action,
        resource_type=str(resource_type),
        resource_id=str(resource_id),
        resource_label=str(resource_label),
        changes=changes,
        source=source,
        request_id=request_id,
    )
