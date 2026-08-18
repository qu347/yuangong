import uuid
from datetime import date

import pytest
from django.core.exceptions import ValidationError
from django.db.models.deletion import ProtectedError

from modules.employees.models import Employee
from modules.organizations.models import Department, Position


@pytest.mark.django_db
def test_directory_models_use_uuid_ids_timestamps_and_expected_defaults():
    department = Department.objects.create(code="ENG", name="研发中心")
    position = Position.objects.create(
        code="ENG-SWE",
        name="软件工程师",
        department=department,
    )
    employee = Employee.objects.create(
        employee_no="EMP-0001",
        full_name="林知远",
        work_email="lin.zhiyuan@example.test",
        department=department,
        position=position,
        hire_date=date(2024, 1, 8),
    )

    assert all(isinstance(item.pk, uuid.UUID) for item in (department, position, employee))
    assert department.status == Department.Status.ACTIVE
    assert position.status == Position.Status.ACTIVE
    assert employee.employment_status == Employee.EmploymentStatus.ACTIVE
    assert all(item.created_at is not None for item in (department, position, employee))
    assert all(item.updated_at is not None for item in (department, position, employee))


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("model", "first", "duplicate"),
    [
        (
            Department,
            {"code": "OPS", "name": "运营中心"},
            {"code": "OPS", "name": "重复部门"},
        ),
        (
            Position,
            {"code": "OPS-MGR", "name": "运营经理"},
            {"code": "OPS-MGR", "name": "重复岗位"},
        ),
    ],
)
def test_department_and_position_codes_are_unique(model, first, duplicate):
    if model is Position:
        department = Department.objects.create(code="OPS-DEP", name="运营部门")
        first["department"] = department
        duplicate["department"] = department
    model.objects.create(**first)

    with pytest.raises(ValidationError):
        model(**duplicate).full_clean()


@pytest.mark.django_db
def test_employee_number_is_unique():
    department = Department.objects.create(code="FIN", name="财务中心")
    Employee.objects.create(
        employee_no="EMP-0002",
        full_name="周予安",
        department=department,
    )

    duplicate = Employee(
        employee_no="EMP-0002",
        full_name="许星河",
        department=department,
    )

    with pytest.raises(ValidationError):
        duplicate.full_clean()


@pytest.mark.django_db
def test_position_requires_a_department():
    position = Position(code="NO-DEP", name="无部门岗位")

    with pytest.raises(ValidationError, match="department"):
        position.full_clean()


@pytest.mark.django_db
def test_department_rejects_itself_as_parent():
    department = Department(code="SELF", name="自引用部门")
    department.parent = department

    with pytest.raises(ValidationError, match="父部门"):
        department.full_clean()


@pytest.mark.django_db
def test_department_rejects_ancestor_cycles():
    root = Department.objects.create(code="ROOT", name="总部")
    child = Department.objects.create(code="CHILD", name="子部门", parent=root)
    root.parent = child

    with pytest.raises(ValidationError, match="循环"):
        root.full_clean()


@pytest.mark.django_db
def test_referenced_department_cannot_be_silently_deleted():
    department = Department.objects.create(code="HR", name="人力资源部")
    Position.objects.create(code="HR-BP", name="人力资源伙伴", department=department)

    with pytest.raises(ProtectedError):
        department.delete()


@pytest.mark.django_db
def test_employee_rejects_a_position_from_another_department():
    engineering = Department.objects.create(code="ENG2", name="研发二部")
    finance = Department.objects.create(code="FIN2", name="财务二部")
    position = Position.objects.create(
        code="FIN-ACC",
        name="会计",
        department=finance,
    )
    employee = Employee(
        employee_no="EMP-0003",
        full_name="程嘉言",
        department=engineering,
        position=position,
    )

    with pytest.raises(ValidationError, match="所属部门"):
        employee.full_clean()
