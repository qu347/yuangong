from rest_framework import serializers

from modules.organizations.models import Department, Position
from modules.organizations.serializers import DepartmentSummarySerializer

from .models import Employee


class PositionSummarySerializer(serializers.Serializer):
    id = serializers.UUIDField(read_only=True)
    code = serializers.CharField(read_only=True)
    name = serializers.CharField(read_only=True)


class ManagerSummarySerializer(serializers.Serializer):
    id = serializers.UUIDField(read_only=True)
    employee_no = serializers.CharField(read_only=True)
    full_name = serializers.CharField(read_only=True)


class EmployeeSerializer(serializers.ModelSerializer):
    department = DepartmentSummarySerializer(read_only=True)
    position = PositionSummarySerializer(read_only=True)

    class Meta:
        model = Employee
        fields = (
            "id",
            "employee_no",
            "full_name",
            "work_email",
            "work_phone",
            "department",
            "position",
            "employment_status",
            "hire_date",
        )


class EmployeeDetailSerializer(EmployeeSerializer):
    manager = ManagerSummarySerializer(read_only=True)

    class Meta(EmployeeSerializer.Meta):
        fields = EmployeeSerializer.Meta.fields + (
            "avatar_url",
            "gender",
            "birthday",
            "office_location",
            "manager",
            "description",
            "updated_at",
        )


class EmployeeWriteSerializer(serializers.ModelSerializer):
    employee_no = serializers.CharField(max_length=50)
    expected_updated_at = serializers.DateTimeField(write_only=True, required=False)

    class Meta:
        model = Employee
        fields = (
            "id",
            "employee_no",
            "full_name",
            "work_email",
            "work_phone",
            "department",
            "position",
            "employment_status",
            "hire_date",
            "avatar_url",
            "gender",
            "birthday",
            "office_location",
            "manager",
            "description",
            "expected_updated_at",
        )
        read_only_fields = ("id", "employment_status")

    def validate(self, attrs):
        instance = self.instance
        department = attrs.get("department", getattr(instance, "department", None))
        position = attrs.get("position", getattr(instance, "position", None))
        if department is not None and department.status != Department.Status.ACTIVE:
            raise serializers.ValidationError({"department": "员工所属部门必须处于启用状态。"})
        if position is not None:
            if position.status != Position.Status.ACTIVE:
                raise serializers.ValidationError({"position": "员工岗位必须处于启用状态。"})
            if department is None or position.department_id != department.pk:
                raise serializers.ValidationError({"position": "岗位必须属于员工当前部门。"})
        return attrs

    def to_representation(self, instance):
        return EmployeeDetailSerializer(instance).data


class EmployeeStatusResponseSerializer(serializers.Serializer):
    employee = EmployeeDetailSerializer(read_only=True)
    changed = serializers.BooleanField(read_only=True)
    account_requires_activation = serializers.BooleanField(read_only=True, required=False)
