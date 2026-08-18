from .services import record_audit_event


def _safe_value(value):
    if hasattr(value, "pk"):
        return str(value.pk)
    if value is None or isinstance(value, (str, int, bool)):
        return value
    return str(value)


class AuditedDirectoryAdminMixin:
    audit_resource_type = None
    audit_fields = ()

    def has_delete_permission(self, request, obj=None):
        del request, obj
        return False

    def save_model(self, request, obj, form, change):
        del form
        before = {}
        if change:
            persisted = type(obj).objects.get(pk=obj.pk)
            before = {field: getattr(persisted, field) for field in self.audit_fields}
        super().save_model(request, obj, None, change)
        after = {field: getattr(obj, field) for field in self.audit_fields}
        changes = {
            field: {"from": _safe_value(before.get(field)), "to": _safe_value(value)}
            for field, value in after.items()
            if _safe_value(before.get(field)) != _safe_value(value)
        }
        if changes:
            record_audit_event(
                actor=request.user,
                action="update" if change else "create",
                resource_type=self.audit_resource_type,
                resource_id=obj.pk,
                resource_label=str(obj),
                changes=changes,
                source="admin",
                request_id=request.headers.get("X-Request-ID"),
            )
