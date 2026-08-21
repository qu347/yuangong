import uuid

from django.db import transaction
from django.db.models import Subquery
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied

from modules.audit.services import record_audit_event

from .exceptions import AttachmentRequestError
from .models import EmployeeAttachment
from .permissions import get_visible_employee, manageable_attachments
from .storage import attachment_storage_path, get_attachment_storage
from .validation import validate_attachment

_MAX_CANONICAL_PATH_ATTEMPTS = 3


def _save_to_new_canonical_path(storage, employee_id, validated, uploaded_file):
    for _attempt in range(_MAX_CANONICAL_PATH_ATTEMPTS):
        attachment_id = uuid.uuid4()
        filename = f"{attachment_id}.{validated.file_type}"
        generated_path = attachment_storage_path(
            employee_id,
            attachment_id,
            validated.file_type,
        )
        uploaded_file.seek(0)
        saved_path = storage.save(generated_path, uploaded_file)
        if saved_path == generated_path:
            return attachment_id, filename, saved_path
        storage.delete(saved_path)

    raise AttachmentRequestError(
        "附件暂时无法保存，请重试。",
        code="attachment_storage_conflict",
    )


def create_attachment(employee, actor, uploaded_file, request_id=None):
    if not actor.has_perm("employees.add_employeeattachment"):
        raise PermissionDenied("当前账号没有上传员工附件的权限。")

    employee_id = getattr(employee, "pk", employee)
    managed_employee = get_visible_employee(actor, employee_id, manage=True)
    if uploaded_file is None:
        raise AttachmentRequestError(
            "请选择要上传的附件。",
            code="attachment_file_missing",
        )
    validated = validate_attachment(uploaded_file)
    storage = get_attachment_storage()
    attachment_id, filename, saved_path = _save_to_new_canonical_path(
        storage,
        managed_employee.pk,
        validated,
        uploaded_file,
    )

    try:
        with transaction.atomic():
            attachment = EmployeeAttachment.objects.create(
                id=attachment_id,
                employee=managed_employee,
                filename=filename,
                original_filename=validated.original_filename,
                file_type=validated.file_type,
                file_size=validated.file_size,
                storage_path=saved_path,
                uploaded_by=actor,
            )
            record_audit_event(
                actor=actor,
                action="employee_attachment.create",
                resource_type="employee_attachment",
                resource_id=attachment.pk,
                resource_label=attachment.original_filename,
                changes={
                    "employee_no": {"to": managed_employee.employee_no},
                    "filename": {"to": attachment.original_filename},
                    "file_type": {"to": attachment.file_type},
                    "file_size": {"to": attachment.file_size},
                },
                source="api",
                request_id=request_id,
            )
        return attachment
    except Exception:
        storage.delete(saved_path)
        raise


def soft_delete_attachment(attachment_id, actor, request_id=None):
    if not actor.has_perm("employees.change_employeeattachment"):
        raise PermissionDenied("当前账号没有删除员工附件的权限。")

    with transaction.atomic():
        manageable_ids = manageable_attachments(actor).values("pk")
        manageable = (
            EmployeeAttachment.objects.filter(
                pk__in=Subquery(manageable_ids),
                deleted_at__isnull=True,
            )
            .select_related("employee")
            .select_for_update(of=("self",))
        )
        attachment = get_object_or_404(manageable, pk=attachment_id)
        get_visible_employee(actor, attachment.employee_id, manage=True)
        attachment.deleted_at = timezone.now()
        attachment.save(update_fields=["deleted_at", "updated_at"])
        record_audit_event(
            actor=actor,
            action="employee_attachment.delete",
            resource_type="employee_attachment",
            resource_id=attachment.pk,
            resource_label=attachment.original_filename,
            changes={"filename": {"from": attachment.original_filename}},
            source="api",
            request_id=request_id,
        )
        return attachment
