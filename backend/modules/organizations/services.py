from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import IntegrityError, transaction
from rest_framework.exceptions import ValidationError

from modules.audit.services import record_audit_event
from modules.common.exceptions import BusinessConflict
from modules.employees.models import Employee

from .models import Department, Position


def _safe_value(value):
    if hasattr(value, "pk"):
        return str(value.pk)
    if value is None or isinstance(value, (str, int, bool)):
        return value
    return str(value)


def _changes(before, after):
    return {
        field: {"from": _safe_value(before.get(field)), "to": _safe_value(value)}
        for field, value in after.items()
        if _safe_value(before.get(field)) != _safe_value(value)
    }


def _save_or_conflict(operation):
    try:
        return operation()
    except IntegrityError as error:
        raise BusinessConflict("目录编号已经存在。", code="uniqueness_conflict") from error
    except DjangoValidationError as error:
        raise ValidationError(
            error.message_dict if hasattr(error, "message_dict") else error.messages
        ) from error


def create_department(*, actor, data, source="api", request_id=None):
    def operation():
        with transaction.atomic():
            department = Department(**data)
            department.full_clean(validate_unique=False)
            department.save()
            record_audit_event(
                actor=actor,
                action="create",
                resource_type="department",
                resource_id=department.pk,
                resource_label=str(department),
                changes=_changes({}, data),
                source=source,
                request_id=request_id,
            )
            return department

    return _save_or_conflict(operation)


def update_department(*, department_id, actor, data, source="api", request_id=None):
    def operation():
        with transaction.atomic():
            department = Department.objects.select_for_update().get(pk=department_id)
            before = {field: getattr(department, field) for field in data}
            for field, value in data.items():
                setattr(department, field, value)
            department.full_clean(validate_unique=False)
            changes = _changes(before, data)
            if changes:
                department.save()
                record_audit_event(
                    actor=actor,
                    action="update",
                    resource_type="department",
                    resource_id=department.pk,
                    resource_label=str(department),
                    changes=changes,
                    source=source,
                    request_id=request_id,
                )
            return department

    return _save_or_conflict(operation)


def set_department_active(*, department_id, active, actor, request_id=None):
    with transaction.atomic():
        department = Department.objects.select_for_update().get(pk=department_id)
        target_status = Department.Status.ACTIVE if active else Department.Status.INACTIVE
        if department.status == target_status:
            return department, False
        if not active:
            dependencies = {
                "active_children": department.children.filter(
                    status=Department.Status.ACTIVE
                ).count(),
                "active_positions": department.positions.filter(
                    status=Position.Status.ACTIVE
                ).count(),
                "active_employees": department.employees.filter(
                    employment_status=Employee.EmploymentStatus.ACTIVE
                ).count(),
            }
            if any(dependencies.values()):
                raise BusinessConflict(dependencies, code="resource_in_use")
        previous = department.status
        department.status = target_status
        department.save(update_fields=["status", "updated_at"])
        record_audit_event(
            actor=actor,
            action="activate" if active else "deactivate",
            resource_type="department",
            resource_id=department.pk,
            resource_label=str(department),
            changes={"status": {"from": previous, "to": target_status}},
            source="api",
            request_id=request_id,
        )
        return department, True


def create_position(*, actor, data, source="api", request_id=None):
    def operation():
        with transaction.atomic():
            department = Department.objects.select_for_update().get(pk=data["department"].pk)
            if department.status != Department.Status.ACTIVE:
                raise ValidationError({"department": "岗位所属部门必须处于启用状态。"})
            data["department"] = department
            position = Position(**data)
            position.full_clean(validate_unique=False)
            position.save()
            record_audit_event(
                actor=actor,
                action="create",
                resource_type="position",
                resource_id=position.pk,
                resource_label=str(position),
                changes=_changes({}, data),
                source=source,
                request_id=request_id,
            )
            return position

    return _save_or_conflict(operation)


def update_position(*, position_id, actor, data, source="api", request_id=None):
    def operation():
        with transaction.atomic():
            position = Position.objects.select_for_update().get(pk=position_id)
            if "department" in data and data["department"].pk != position.department_id:
                if position.employees.exists():
                    raise BusinessConflict(
                        {"employees": position.employees.count()}, code="resource_in_use"
                    )
                if data["department"].status != Department.Status.ACTIVE:
                    raise ValidationError({"department": "岗位所属部门必须处于启用状态。"})
            before = {field: getattr(position, field) for field in data}
            for field, value in data.items():
                setattr(position, field, value)
            position.full_clean(validate_unique=False)
            changes = _changes(before, data)
            if changes:
                position.save()
                record_audit_event(
                    actor=actor,
                    action="update",
                    resource_type="position",
                    resource_id=position.pk,
                    resource_label=str(position),
                    changes=changes,
                    source=source,
                    request_id=request_id,
                )
            return position

    return _save_or_conflict(operation)


def set_position_active(*, position_id, active, actor, request_id=None):
    with transaction.atomic():
        position = (
            Position.objects.select_for_update().select_related("department").get(pk=position_id)
        )
        target_status = Position.Status.ACTIVE if active else Position.Status.INACTIVE
        if position.status == target_status:
            return position, False
        if active and position.department.status != Department.Status.ACTIVE:
            raise BusinessConflict("岗位所属部门未启用。", code="invalid_state_transition")
        if not active:
            active_employees = position.employees.filter(
                employment_status=Employee.EmploymentStatus.ACTIVE
            ).count()
            if active_employees:
                raise BusinessConflict(
                    {"active_employees": active_employees}, code="resource_in_use"
                )
        previous = position.status
        position.status = target_status
        position.save(update_fields=["status", "updated_at"])
        record_audit_event(
            actor=actor,
            action="activate" if active else "deactivate",
            resource_type="position",
            resource_id=position.pk,
            resource_label=str(position),
            changes={"status": {"from": previous, "to": target_status}},
            source="api",
            request_id=request_id,
        )
        return position, True
