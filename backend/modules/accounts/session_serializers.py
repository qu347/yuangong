from rest_framework import serializers

from .models import AccountSession


class AccountSessionSerializer(serializers.ModelSerializer):
    is_current = serializers.SerializerMethodField()

    class Meta:
        model = AccountSession
        fields = (
            "id",
            "client_platform",
            "client_name",
            "app_version",
            "created_at",
            "last_seen_at",
            "expires_at",
            "is_current",
        )
        read_only_fields = fields

    def get_is_current(self, session):
        return str(session.id) == str(self.context.get("current_sid"))


class SessionRevokeResponseSerializer(serializers.Serializer):
    changed = serializers.BooleanField(read_only=True)
    is_current = serializers.BooleanField(read_only=True)


class SessionCountResponseSerializer(serializers.Serializer):
    revoked_sessions = serializers.IntegerField(min_value=0, read_only=True)
