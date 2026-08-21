from rest_framework import serializers

from .models import EmployeeAttachment


class AttachmentUploaderSerializer(serializers.Serializer):
    id = serializers.UUIDField(read_only=True)
    username = serializers.CharField(read_only=True)


class EmployeeAttachmentSerializer(serializers.ModelSerializer):
    employee_id = serializers.UUIDField(read_only=True)
    filename = serializers.CharField(source="original_filename", read_only=True)
    uploaded_by = AttachmentUploaderSerializer(read_only=True)

    class Meta:
        model = EmployeeAttachment
        fields = [
            "id",
            "employee_id",
            "filename",
            "file_type",
            "file_size",
            "uploaded_by",
            "created_at",
        ]
        read_only_fields = fields


class EmployeeAttachmentUploadSerializer(serializers.Serializer):
    file = serializers.FileField(required=False, allow_empty_file=True, write_only=True)
