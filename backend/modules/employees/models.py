import uuid

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models

from modules.organizations.models import Department, Position


class Employee(models.Model):
    class EmploymentStatus(models.TextChoices):
        ACTIVE = "active", "在职"
        DEPARTED = "departed", "离职"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    employee_no = models.CharField(max_length=50, unique=True)
    full_name = models.CharField(max_length=100)
    work_email = models.EmailField(blank=True)
    work_phone = models.CharField(max_length=50, blank=True)
    department = models.ForeignKey(
        Department,
        on_delete=models.PROTECT,
        related_name="employees",
    )
    position = models.ForeignKey(
        Position,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="employees",
    )
    employment_status = models.CharField(
        max_length=16,
        choices=EmploymentStatus.choices,
        default=EmploymentStatus.ACTIVE,
    )
    hire_date = models.DateField(null=True, blank=True)
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="employee_profile",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["employee_no"]
        verbose_name = "员工"
        verbose_name_plural = "员工"
        indexes = [models.Index(fields=["department", "employment_status"])]

    def __str__(self):
        return f"{self.employee_no} · {self.full_name}"

    def clean(self):
        super().clean()
        if (
            self.position_id is not None
            and self.position.department_id is not None
            and self.position.department_id != self.department_id
        ):
            raise ValidationError({"position": "岗位所属部门必须与员工所属部门一致。"})
