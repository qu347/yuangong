from rest_framework import serializers

from modules.organizations.serializers import DepartmentSummarySerializer

from .models import Employee


class PositionSummarySerializer(serializers.Serializer):
    id = serializers.UUIDField(read_only=True)
    code = serializers.CharField(read_only=True)
    name = serializers.CharField(read_only=True)


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
