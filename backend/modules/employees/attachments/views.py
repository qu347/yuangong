import re
import unicodedata

from django.http import FileResponse
from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema, extend_schema_view
from rest_framework import generics, status
from rest_framework.exceptions import PermissionDenied
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from modules.common.pagination import DirectoryPagination

from .exceptions import AttachmentFileMissing
from .permissions import get_visible_employee, visible_attachments
from .serializers import EmployeeAttachmentSerializer, EmployeeAttachmentUploadSerializer
from .services import create_attachment, soft_delete_attachment
from .storage import get_attachment_storage

FILE_TYPE_CONTENT_TYPES = {
    "pdf": "application/pdf",
    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "jpg": "image/jpeg",
    "png": "image/png",
}


def _safe_download_filename(original_filename, file_type):
    first_line = re.split(r"[\r\n]", str(original_filename), maxsplit=1)[0]
    basename = re.split(r"[\\/]", first_line)[-1]
    sanitized = "".join(
        character
        for character in basename
        if unicodedata.category(character) not in {"Cc", "Cf"} and character not in '\\";'
    ).strip()
    return sanitized if sanitized else f"attachment.{file_type}"


@extend_schema_view(
    get=extend_schema(responses=EmployeeAttachmentSerializer(many=True)),
    post=extend_schema(
        request={
            "multipart/form-data": {
                "type": "object",
                "properties": {
                    "file": {"type": "string", "format": "binary"},
                },
                "required": ["file"],
            }
        },
        responses={status.HTTP_201_CREATED: EmployeeAttachmentSerializer},
    ),
)
class EmployeeAttachmentListCreateView(generics.ListCreateAPIView):
    permission_classes = [IsAuthenticated]
    pagination_class = DirectoryPagination
    parser_classes = [MultiPartParser, FormParser]

    def get_serializer_class(self):
        if self.request.method == "POST":
            return EmployeeAttachmentUploadSerializer
        return EmployeeAttachmentSerializer

    def get_queryset(self):
        employee = get_visible_employee(
            self.request.user,
            self.kwargs["employee_id"],
        )
        return visible_attachments(self.request.user).filter(employee_id=employee.pk)

    def create(self, request, *args, **kwargs):
        del args
        if not request.user.has_perm("employees.add_employeeattachment"):
            raise PermissionDenied("当前账号没有上传员工附件的权限。")
        get_visible_employee(
            request.user,
            kwargs["employee_id"],
            manage=True,
        )
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        attachment = create_attachment(
            kwargs["employee_id"],
            request.user,
            serializer.validated_data.get("file"),
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response(
            EmployeeAttachmentSerializer(attachment).data,
            status=status.HTTP_201_CREATED,
        )


class EmployeeAttachmentDownloadView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(
        responses={
            (status.HTTP_200_OK, content_type): OpenApiTypes.BINARY
            for content_type in FILE_TYPE_CONTENT_TYPES.values()
        }
    )
    def get(self, request, attachment_id):
        attachment = get_object_or_404(
            visible_attachments(request.user),
            pk=attachment_id,
        )
        storage = get_attachment_storage()
        if not storage.exists(attachment.storage_path):
            raise AttachmentFileMissing()
        try:
            stored_file = storage.open(attachment.storage_path, "rb")
        except FileNotFoundError as error:
            raise AttachmentFileMissing() from error

        response = FileResponse(
            stored_file,
            as_attachment=True,
            filename=_safe_download_filename(
                attachment.original_filename,
                attachment.file_type,
            ),
            content_type=FILE_TYPE_CONTENT_TYPES[attachment.file_type],
        )
        response["Cache-Control"] = "private, no-store"
        response["X-Content-Type-Options"] = "nosniff"
        return response


class EmployeeAttachmentDetailView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(request=None, responses={status.HTTP_204_NO_CONTENT: None})
    def delete(self, request, attachment_id):
        soft_delete_attachment(
            attachment_id,
            request.user,
            request_id=request.headers.get("X-Request-ID"),
        )
        return Response(status=status.HTTP_204_NO_CONTENT)
