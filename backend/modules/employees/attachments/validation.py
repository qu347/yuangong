import re
import unicodedata
from dataclasses import dataclass
from pathlib import PurePath
from zipfile import BadZipFile, LargeZipFile, ZipFile

from django.conf import settings

from .exceptions import AttachmentRequestError

_EXTENSION_TO_FILE_TYPE = {
    "pdf": "pdf",
    "docx": "docx",
    "xlsx": "xlsx",
    "jpg": "jpg",
    "jpeg": "jpg",
    "png": "png",
}
_HEADER_UNSAFE_CHARACTERS = frozenset('\\";')


@dataclass(frozen=True)
class ValidatedAttachment:
    original_filename: str
    file_type: str
    file_size: int


def validate_attachment(uploaded_file):
    try:
        original_filename = _sanitize_original_filename(uploaded_file.name)
        extension = PurePath(original_filename).suffix.removeprefix(".").lower()
        file_type = _EXTENSION_TO_FILE_TYPE.get(extension)
        if file_type is None:
            raise AttachmentRequestError(
                "附件类型不受支持。",
                code="attachment_type_not_allowed",
            )

        file_size = uploaded_file.size
        if file_size <= 0:
            raise AttachmentRequestError(
                "附件内容无效。",
                code="attachment_invalid_content",
            )
        if file_size > settings.EMPLOYEE_ATTACHMENT_MAX_BYTES:
            raise AttachmentRequestError(
                "附件大小不能超过 10 MiB。",
                code="attachment_too_large",
            )

        uploaded_file.seek(0)
        if not _has_valid_content(uploaded_file, file_type):
            raise AttachmentRequestError(
                "附件内容与文件类型不匹配。",
                code="attachment_invalid_content",
            )

        return ValidatedAttachment(
            original_filename=original_filename,
            file_type=file_type,
            file_size=file_size,
        )
    finally:
        uploaded_file.seek(0)


def _sanitize_original_filename(name):
    basename = re.split(r"[\\/]", str(name))[-1]
    sanitized = "".join(
        character
        for character in basename
        if unicodedata.category(character) not in {"Cc", "Cf"}
        and character not in _HEADER_UNSAFE_CHARACTERS
    ).strip()

    extension = PurePath(sanitized).suffix
    if not PurePath(sanitized).stem:
        sanitized = f"attachment{extension}"
    if len(sanitized) > 255:
        sanitized = f"{sanitized[: 255 - len(extension)]}{extension}"
    return sanitized


def _has_valid_content(uploaded_file, file_type):
    if file_type == "pdf":
        return uploaded_file.read(5) == b"%PDF-"
    if file_type == "jpg":
        return uploaded_file.read(3) == b"\xff\xd8\xff"
    if file_type == "png":
        return uploaded_file.read(8) == b"\x89PNG\r\n\x1a\n"
    return _has_valid_ooxml_structure(uploaded_file, file_type)


def _has_valid_ooxml_structure(uploaded_file, file_type):
    required_document_member = {
        "docx": "word/document.xml",
        "xlsx": "xl/workbook.xml",
    }[file_type]
    try:
        with ZipFile(uploaded_file) as archive:
            members = set(archive.namelist())
    except (BadZipFile, LargeZipFile, OSError, ValueError):
        return False

    return "[Content_Types].xml" in members and required_document_member in members
