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
