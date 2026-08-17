from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import IntegrityError, transaction
from rest_framework.exceptions import ValidationError

from modules.accounts.tokens import revoke_all_user_tokens
from modules.audit.services import record_audit_event
from modules.common.exceptions import BusinessConflict
from modules.organizations.models import Department, Position

from .models import Employee


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
        raise BusinessConflict("员工编号已经存在。", code="uniqueness_conflict") from error
    except DjangoValidationError as error:
        raise ValidationError(
            error.message_dict if hasattr(error, "message_dict") else error.messages
        ) from error


def _lock_active_relationships(data, *, current=None):
    department = data.get("department", getattr(current, "department", None))
    position = data.get("position", getattr(current, "position", None))
    if department is None:
        raise ValidationError({"department": "必须选择部门。"})
    department = Department.objects.select_for_update().get(pk=department.pk)
    if department.status != Department.Status.ACTIVE:
        raise ValidationError({"department": "员工所属部门必须处于启用状态。"})
    if position is not None:
        position = Position.objects.select_for_update().get(pk=position.pk)
        if position.status != Position.Status.ACTIVE:
            raise ValidationError({"position": "员工岗位必须处于启用状态。"})
        if position.department_id != department.pk:
            raise ValidationError({"position": "岗位必须属于员工当前部门。"})
    data["department"] = department
    if "position" in data or position is not None:
        data["position"] = position
    return data


def create_employee(*, actor, data, source="api", request_id=None):
    def operation():
        with transaction.atomic():
            data.pop("expected_updated_at", None)
            _lock_active_relationships(data)
            employee = Employee(**data)
            employee.full_clean(validate_unique=False)
            employee.save()
            record_audit_event(
                actor=actor,
                action="create",
                resource_type="employee",
                resource_id=employee.pk,
                resource_label=str(employee),
                changes=_changes({}, data),
                source=source,
                request_id=request_id,
            )
            return employee

    return _save_or_conflict(operation)


def update_employee(*, employee_id, actor, data, source="api", request_id=None):
    def operation():
        with transaction.atomic():
            employee = Employee.objects.select_for_update().get(pk=employee_id)
            expected_updated_at = data.pop("expected_updated_at", None)
            if expected_updated_at is not None and expected_updated_at != employee.updated_at:
                raise BusinessConflict(
                    "员工目录已经被其他操作更新，请重新加载。", code="stale_object"
                )
            _lock_active_relationships(data, current=employee)
            before = {field: getattr(employee, field) for field in data}
            for field, value in data.items():
                setattr(employee, field, value)
            employee.full_clean(validate_unique=False)
            changes = _changes(before, data)
            if changes:
                employee.save()
                record_audit_event(
                    actor=actor,
                    action="update",
                    resource_type="employee",
                    resource_id=employee.pk,
                    resource_label=str(employee),
                    changes=changes,
                    source=source,
                    request_id=request_id,
                )
            return employee

    return _save_or_conflict(operation)


def depart_employee(*, employee_id, actor, request_id=None):
    with transaction.atomic():
        employee = (
            Employee.objects.select_for_update(of=("self",))
            .select_related("user", "department", "position")
            .get(pk=employee_id)
        )
        if employee.employment_status == Employee.EmploymentStatus.DEPARTED:
            return employee, False
        previous = employee.employment_status
        employee.employment_status = Employee.EmploymentStatus.DEPARTED
        employee.save(update_fields=["employment_status", "updated_at"])
        record_audit_event(
            actor=actor,
            action="depart",
            resource_type="employee",
            resource_id=employee.pk,
            resource_label=str(employee),
            changes={"employment_status": {"from": previous, "to": employee.employment_status}},
            source="api",
            request_id=request_id,
        )
        if employee.user is not None and employee.user.is_active:
            employee.user.is_active = False
            employee.user.save(update_fields=["is_active", "updated_at"])
            revoked_sessions = revoke_all_user_tokens(employee.user)
            record_audit_event(
                actor=actor,
                action="account_deactivate",
                resource_type="user",
                resource_id=employee.user.pk,
                resource_label=employee.user.username,
                changes={
                    "is_active": {"from": True, "to": False},
                    "revoked_sessions": {"to": revoked_sessions},
                },
                source="api",
                request_id=request_id,
            )
        return employee, True


def reactivate_employee(*, employee_id, actor, request_id=None):
    with transaction.atomic():
        employee = (
            Employee.objects.select_for_update(of=("self",))
            .select_related("user", "department", "position")
            .get(pk=employee_id)
        )
        if employee.employment_status == Employee.EmploymentStatus.ACTIVE:
            return employee, False
        if employee.department.status != Department.Status.ACTIVE:
            raise BusinessConflict("员工部门未启用。", code="invalid_state_transition")
        if employee.position is not None and employee.position.status != Position.Status.ACTIVE:
            raise BusinessConflict("员工岗位未启用。", code="invalid_state_transition")
        previous = employee.employment_status
        employee.employment_status = Employee.EmploymentStatus.ACTIVE
        employee.save(update_fields=["employment_status", "updated_at"])
        record_audit_event(
            actor=actor,
            action="reactivate",
            resource_type="employee",
            resource_id=employee.pk,
            resource_label=str(employee),
            changes={"employment_status": {"from": previous, "to": employee.employment_status}},
            source="api",
            request_id=request_id,
        )
        return employee, True
