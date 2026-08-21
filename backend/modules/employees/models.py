import uuid

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models

from modules.organizations.models import Department, Position

from .attachments.models import EmployeeAttachment  # noqa: F401


class Employee(models.Model):
    class EmploymentStatus(models.TextChoices):
        ACTIVE = "active", "在职"
        DEPARTED = "departed", "离职"

    class Gender(models.TextChoices):
        UNSPECIFIED = "unspecified", "未填写"
        FEMALE = "female", "女"
        MALE = "male", "男"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    employee_no = models.CharField(max_length=50, unique=True)
    full_name = models.CharField(max_length=100, db_index=True)
    work_email = models.EmailField(blank=True, db_index=True)
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
    avatar_url = models.URLField(max_length=500, blank=True)
    gender = models.CharField(
        max_length=16,
        choices=Gender.choices,
        default=Gender.UNSPECIFIED,
    )
    birthday = models.DateField(null=True, blank=True)
    office_location = models.CharField(max_length=200, blank=True)
    manager = models.ForeignKey(
        "self",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="direct_reports",
    )
    description = models.TextField(max_length=1000, blank=True)
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
        errors = {}
        if self.avatar_url and not self.avatar_url.lower().startswith("https://"):
            errors["avatar_url"] = "头像地址必须使用 HTTPS。"
        if self.manager_id is not None:
            if self.manager_id == self.pk:
                errors["manager"] = "员工不能成为自己的直属负责人。"
            else:
                current = self.manager
                visited = set()
                while current is not None:
                    if current.pk == self.pk or current.pk in visited:
                        errors["manager"] = "直属负责人关系不能形成循环。"
                        break
                    visited.add(current.pk)
                    current = current.manager
        if errors:
            raise ValidationError(errors)
