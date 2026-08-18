from django.utils import timezone
from rest_framework import serializers

from .models import AccountInvitation


class AccountInvitationSerializer(serializers.ModelSerializer):
    employee_id = serializers.UUIDField(read_only=True)
    status = serializers.SerializerMethodField()

    class Meta:
        model = AccountInvitation
        fields = (
            "id",
            "employee_id",
            "email",
            "username",
            "target_role",
            "status",
            "expires_at",
            "send_count",
            "last_sent_at",
            "created_at",
            "updated_at",
        )
        read_only_fields = fields

    def get_status(self, invitation):
        if invitation.accepted_at is not None:
            return "accepted"
        if invitation.revoked_at is not None:
            return "revoked"
        return "expired" if invitation.expires_at <= timezone.now() else "pending"


class AccountInvitationCreateSerializer(serializers.Serializer):
    employee_id = serializers.UUIDField()
    username = serializers.CharField(max_length=150, trim_whitespace=True)
    email = serializers.EmailField(required=False, allow_blank=True)
    target_role = serializers.ChoiceField(choices=AccountInvitation.TargetRole.choices)


class InvitationAcceptSerializer(serializers.Serializer):
    token = serializers.CharField(write_only=True, trim_whitespace=True)
    new_password = serializers.CharField(write_only=True, trim_whitespace=False)


class InvitationActionResponseSerializer(serializers.Serializer):
    changed = serializers.BooleanField(read_only=True)
