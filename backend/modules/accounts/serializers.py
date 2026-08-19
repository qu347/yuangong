from django.contrib.auth import authenticate
from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers
from rest_framework.exceptions import AuthenticationFailed

from .models import AccountSession, User
from .sessions import issue_session_tokens, rotate_session_refresh


class LoginSerializer(serializers.Serializer):
    identifier = serializers.CharField(required=False, trim_whitespace=True)
    username = serializers.CharField(required=False, trim_whitespace=True)
    password = serializers.CharField(write_only=True, trim_whitespace=False)
    client_platform = serializers.ChoiceField(
        choices=AccountSession.ClientPlatform.choices,
        required=False,
        default=AccountSession.ClientPlatform.UNKNOWN,
    )
    client_name = serializers.CharField(required=False, allow_blank=True, max_length=80)
    app_version = serializers.CharField(required=False, allow_blank=True, max_length=32)

    default_error_messages = {
        "no_active_account": "登录名或密码错误。",
    }

    def validate(self, attrs):
        identifier = attrs.get("identifier")
        username = attrs.get("username")
        if bool(identifier) == bool(username):
            raise serializers.ValidationError("identifier 与 username 必须且只能提供一个。")
        resolved_identifier = (identifier or username).strip()
        candidates = (
            User.objects.filter(email__iexact=resolved_identifier)
            if "@" in resolved_identifier
            else User.objects.filter(username=resolved_identifier)
        )
        if candidates.count() != 1:
            raise AuthenticationFailed(self.error_messages["no_active_account"])
        candidate = candidates.first()
        user = authenticate(
            request=self.context.get("request"),
            username=candidate.username,
            password=attrs["password"],
        )
        if user is None or not user.is_active:
            raise AuthenticationFailed(self.error_messages["no_active_account"])
        issued = issue_session_tokens(
            user,
            platform=attrs.get("client_platform", AccountSession.ClientPlatform.UNKNOWN),
            client_name=attrs.get("client_name", ""),
            app_version=attrs.get("app_version", ""),
        )
        self.user = user
        return {
            "access": issued.access,
            "refresh": issued.refresh,
            "session": {
                "id": str(issued.session.id),
                "client_platform": issued.session.client_platform,
                "client_name": issued.session.client_name,
                "app_version": issued.session.app_version,
            },
        }


class LoginSessionSerializer(serializers.Serializer):
    id = serializers.UUIDField(read_only=True)
    client_platform = serializers.ChoiceField(
        choices=AccountSession.ClientPlatform.choices,
        read_only=True,
    )
    client_name = serializers.CharField(read_only=True)
    app_version = serializers.CharField(read_only=True)


class LoginResponseSerializer(serializers.Serializer):
    access = serializers.CharField(read_only=True)
    refresh = serializers.CharField(read_only=True)
    session = LoginSessionSerializer(read_only=True)


class ActiveUserTokenRefreshSerializer(serializers.Serializer):
    refresh = serializers.CharField(trim_whitespace=False)
    access = serializers.CharField(read_only=True)

    def validate(self, attrs):
        return rotate_session_refresh(attrs["refresh"])


class LogoutSerializer(serializers.Serializer):
    refresh = serializers.CharField(write_only=True, trim_whitespace=False)


class LogoutAllResponseSerializer(serializers.Serializer):
    revoked_sessions = serializers.IntegerField(min_value=0, read_only=True)


class CurrentUserDepartmentSerializer(serializers.Serializer):
    id = serializers.UUIDField(read_only=True)
    code = serializers.CharField(read_only=True)
    name = serializers.CharField(read_only=True)


class CurrentUserSerializer(serializers.Serializer):
    id = serializers.UUIDField(read_only=True)
    username = serializers.CharField(read_only=True)
    display_name = serializers.SerializerMethodField()
    employee_id = serializers.SerializerMethodField()
    employee_no = serializers.SerializerMethodField()
    department = serializers.SerializerMethodField()
    roles = serializers.SerializerMethodField()
    capabilities = serializers.SerializerMethodField()

    @staticmethod
    def _employee(user):
        return getattr(user, "employee_profile", None)

    @extend_schema_field(serializers.CharField())
    def get_display_name(self, user):
        employee = self._employee(user)
        if employee is not None:
            return employee.full_name
        return user.get_full_name() or user.username

    @extend_schema_field(serializers.UUIDField(allow_null=True))
    def get_employee_id(self, user):
        employee = self._employee(user)
        return employee.id if employee is not None else None

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_employee_no(self, user):
        employee = self._employee(user)
        return employee.employee_no if employee is not None else None

    @extend_schema_field(CurrentUserDepartmentSerializer(allow_null=True))
    def get_department(self, user):
        employee = self._employee(user)
        if employee is None:
            return None
        department = employee.department
        return {
            "id": department.id,
            "code": department.code,
            "name": department.name,
        }

    @extend_schema_field(serializers.ListField(child=serializers.CharField()))
    def get_roles(self, user):
        roles = set(user.groups.values_list("name", flat=True))
        if user.is_superuser:
            roles.add("system_admin")
        return sorted(roles)

    @extend_schema_field(serializers.DictField(child=serializers.BooleanField(), read_only=True))
    def get_capabilities(self, user):
        return {
            "can_manage_employees": user.has_perms(
                ("employees.add_employee", "employees.change_employee")
            ),
            "can_manage_departments": user.has_perms(
                ("organizations.add_department", "organizations.change_department")
            ),
            "can_manage_positions": user.has_perms(
                ("organizations.add_position", "organizations.change_position")
            ),
            "can_view_audit": user.has_perm("audit.view_auditevent"),
            "can_logout_all": user.is_authenticated,
            "can_manage_accounts": user.has_perm("accounts.change_user"),
            "can_invite_accounts": user.has_perm("accounts.add_accountinvitation"),
            "can_manage_account_roles": user.has_perm("accounts.change_user"),
            "can_view_sessions": user.is_authenticated,
            "can_revoke_other_sessions": user.is_authenticated,
            "can_change_password": user.is_authenticated,
        }
