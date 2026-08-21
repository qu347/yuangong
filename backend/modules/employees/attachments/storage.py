from pathlib import PurePosixPath
from uuid import UUID

from django.conf import settings
from django.core.files.storage import FileSystemStorage

from .models import EmployeeAttachment


def attachment_storage_path(employee_id, attachment_id, file_type):
    employee_uuid = UUID(str(employee_id))
    attachment_uuid = UUID(str(attachment_id))
    if file_type not in EmployeeAttachment.FileType.values:
        raise ValueError("Unsupported canonical attachment file type")

    return PurePosixPath(
        "employee",
        str(employee_uuid),
        f"{attachment_uuid}.{file_type}",
    ).as_posix()


def get_attachment_storage():
    return FileSystemStorage(location=settings.EMPLOYEE_ATTACHMENT_STORAGE_ROOT)
