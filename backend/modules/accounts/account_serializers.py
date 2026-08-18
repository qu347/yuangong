from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers

from .account_services import managed_role
from .models import AccountInvitation, User


class AccountEmployeeSerializer(serializers.Serializer):
    id = serializers.UUIDField(read_only=True)
    employee_no = serializers.CharField(read_only=True)
    full_name = serializers.CharField(read_only=True)
    employment_status = serializers.CharField(read_only=True)
    work_email = serializers.EmailField(read_only=True)


class AccountSerializer(serializers.ModelSerializer):
    employee = serializers.SerializerMethodField()
    role = serializers.SerializerMethodField()
    has_active_invitation = serializers.SerializerMethodField()
    email_mismatch = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = (
            "id",
            "username",
            "email",
            "is_active",
            "last_login",
            "employee",
            "role",
            "has_active_invitation",
            "email_mismatch",
        )
        read_only_fields = fields

    @extend_schema_field(AccountEmployeeSerializer(allow_null=True))
    def get_employee(self, user):
        employee = getattr(user, "employee_profile", None)
        return AccountEmployeeSerializer(employee).data if employee else None

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_role(self, user):
        return managed_role(user)

    @extend_schema_field(serializers.BooleanField())
    def get_has_active_invitation(self, user):
        employee = getattr(user, "employee_profile", None)
        if employee is None:
            return False
        return AccountInvitation.objects.filter(
            employee=employee,
            accepted_at=None,
            revoked_at=None,
        ).exists()

    @extend_schema_field(serializers.BooleanField())
    def get_email_mismatch(self, user):
        employee = getattr(user, "employee_profile", None)
        return bool(
            employee
            and employee.work_email
            and employee.work_email.casefold() != user.email.casefold()
        )


class AccountUpdateSerializer(serializers.Serializer):
    email = serializers.EmailField()


class AccountRoleChangeSerializer(serializers.Serializer):
    role = serializers.ChoiceField(choices=("employee", "hr_admin"))


class AccountActionResponseSerializer(serializers.Serializer):
    account = AccountSerializer(read_only=True)
    changed = serializers.BooleanField(read_only=True)


class AccountSessionRevokeResponseSerializer(serializers.Serializer):
    revoked_sessions = serializers.IntegerField(min_value=0, read_only=True)
