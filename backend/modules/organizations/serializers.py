from rest_framework import serializers

from .models import Department, Position


class DepartmentSummarySerializer(serializers.ModelSerializer):
    class Meta:
        model = Department
        fields = ("id", "code", "name")


class DepartmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Department
        fields = ("id", "code", "name", "parent", "status", "sort_order")


class PositionSerializer(serializers.ModelSerializer):
    department = DepartmentSummarySerializer(read_only=True)

    class Meta:
        model = Position
        fields = ("id", "code", "name", "department", "status")


class DepartmentWriteSerializer(serializers.ModelSerializer):
    code = serializers.CharField(max_length=50)

    class Meta:
        model = Department
        fields = ("id", "code", "name", "parent", "status", "sort_order")
        read_only_fields = ("id", "status")

    def validate_parent(self, parent):
        if parent is not None and parent.status != Department.Status.ACTIVE:
            raise serializers.ValidationError("父部门必须处于启用状态。")
        return parent


class PositionWriteSerializer(serializers.ModelSerializer):
    code = serializers.CharField(max_length=50)

    class Meta:
        model = Position
        fields = ("id", "code", "name", "department", "status")
        read_only_fields = ("id", "status")

    def to_representation(self, instance):
        return PositionSerializer(instance).data
