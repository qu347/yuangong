from datetime import date

import pytest
from django.db import IntegrityError, models

from modules.accounts.models import User
from modules.employees.models import Employee, EmployeeAttachment
from modules.organizations.models import Department


@pytest.fixture
def attachment_employee(db):
    department = Department.objects.create(code="ATT", name="附件测试部门")
    return Employee.objects.create(
        employee_no="EMP-ATT-0001",
        full_name="附件测试员工",
        department=department,
        hire_date=date(2024, 1, 1),
    )


@pytest.mark.django_db
def test_attachment_model_keeps_only_safe_metadata(attachment_employee):
    user = User.objects.create_user(username="attachment_uploader")

    attachment = EmployeeAttachment.objects.create(
        employee=attachment_employee,
        filename="00000000-0000-0000-0000-000000000901.pdf",
        original_filename="合同.pdf",
        file_type="pdf",
        file_size=1024,
        storage_path=(
            f"employee/{attachment_employee.id}/00000000-0000-0000-0000-000000000901.pdf"
        ),
        uploaded_by=user,
    )

    assert attachment.deleted_at is None
    assert not any(isinstance(field, models.BinaryField) for field in attachment._meta.fields)
    assert EmployeeAttachment._meta.ordering == ["-created_at", "-id"]
    assert any(
        index.fields == ["employee", "deleted_at", "created_at"]
        for index in EmployeeAttachment._meta.indexes
    )


@pytest.mark.django_db
@pytest.mark.parametrize("file_size", [0, 10 * 1024 * 1024 + 1])
def test_attachment_model_rejects_sizes_outside_configured_bounds(attachment_employee, file_size):
    with pytest.raises(IntegrityError):
        EmployeeAttachment.objects.create(
            employee=attachment_employee,
            filename="00000000-0000-0000-0000-000000000902.pdf",
            original_filename="合同.pdf",
            file_type="pdf",
            file_size=file_size,
            storage_path=(
                f"employee/{attachment_employee.id}/00000000-0000-0000-0000-000000000902.pdf"
            ),
        )
