from rest_framework import serializers

from .models import AuditEvent


class AuditActorSerializer(serializers.Serializer):
    id = serializers.UUIDField(read_only=True)
    username = serializers.CharField(read_only=True)


class AuditEventSerializer(serializers.ModelSerializer):
    actor = AuditActorSerializer(read_only=True)

    class Meta:
        model = AuditEvent
        fields = (
            "id",
            "actor",
            "action",
            "resource_type",
            "resource_id",
            "resource_label",
            "changes",
            "source",
            "request_id",
            "created_at",
        )
        read_only_fields = fields
