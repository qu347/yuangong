from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer, TokenRefreshSerializer


class LoginSerializer(TokenObtainPairSerializer):
    default_error_messages = {
        "no_active_account": "登录名或密码错误。",
    }


class ActiveUserTokenRefreshSerializer(TokenRefreshSerializer):
    default_error_messages = {
        "no_active_account": "账号已停用，无法刷新会话。",
    }


class LogoutSerializer(serializers.Serializer):
    refresh = serializers.CharField(write_only=True, trim_whitespace=False)


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
        }
