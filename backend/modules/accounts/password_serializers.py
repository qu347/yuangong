from rest_framework import serializers


class PasswordResetRequestSerializer(serializers.Serializer):
    identifier = serializers.CharField(trim_whitespace=True)


class PasswordResetAcceptedSerializer(serializers.Serializer):
    message = serializers.CharField(read_only=True)


class PasswordResetConfirmSerializer(serializers.Serializer):
    token = serializers.CharField(write_only=True, trim_whitespace=True)
    new_password = serializers.CharField(write_only=True, trim_whitespace=False)


class PasswordChangeSerializer(serializers.Serializer):
    current_password = serializers.CharField(write_only=True, trim_whitespace=False)
    new_password = serializers.CharField(write_only=True, trim_whitespace=False)
