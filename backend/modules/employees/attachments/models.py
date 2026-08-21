import uuid

from django.conf import settings
from django.db import models


class EmployeeAttachment(models.Model):
    class FileType(models.TextChoices):
        PDF = "pdf", "PDF"
        DOCX = "docx", "DOCX"
        XLSX = "xlsx", "XLSX"
        JPG = "jpg", "JPG"
        PNG = "png", "PNG"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    employee = models.ForeignKey(
        "employees.Employee",
        on_delete=models.PROTECT,
        related_name="attachments",
    )
    filename = models.CharField(max_length=255)
    original_filename = models.CharField(max_length=255)
    file_type = models.CharField(max_length=8, choices=FileType.choices)
    file_size = models.PositiveBigIntegerField()
    storage_path = models.CharField(max_length=500, unique=True)
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="uploaded_employee_attachments",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at", "-id"]
        indexes = [models.Index(fields=["employee", "deleted_at", "created_at"])]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(file_size__gte=1)
                & models.Q(file_size__lte=settings.EMPLOYEE_ATTACHMENT_MAX_BYTES),
                name="employee_attach_file_size_range",
            )
        ]
        verbose_name = "员工附件"
        verbose_name_plural = "员工附件"

    def __str__(self):
        return self.original_filename
