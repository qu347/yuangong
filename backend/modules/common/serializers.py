from rest_framework import serializers


class RecentOperationSerializer(serializers.Serializer):
    id = serializers.UUIDField(read_only=True)
    action = serializers.CharField(read_only=True)
    resource_type = serializers.CharField(read_only=True)
    resource_id = serializers.CharField(read_only=True)
    resource_label = serializers.CharField(read_only=True)
    created_at = serializers.DateTimeField(read_only=True)


class DashboardSummarySerializer(serializers.Serializer):
    employee_total = serializers.IntegerField(read_only=True)
    active_employee = serializers.IntegerField(read_only=True)
    departed_employee = serializers.IntegerField(read_only=True)
    department_total = serializers.IntegerField(read_only=True)
    position_total = serializers.IntegerField(read_only=True)
    recent_operations = RecentOperationSerializer(many=True, read_only=True)


class DepartmentHeadcountSerializer(serializers.Serializer):
    department_id = serializers.UUIDField(read_only=True)
    department_name = serializers.CharField(read_only=True)
    count = serializers.IntegerField(read_only=True)


class TrendPointSerializer(serializers.Serializer):
    month = serializers.CharField(read_only=True)
    count = serializers.IntegerField(read_only=True)


class DistributionPointSerializer(serializers.Serializer):
    label = serializers.CharField(read_only=True)
    count = serializers.IntegerField(read_only=True)


class HrStatisticsSerializer(serializers.Serializer):
    employee_total = serializers.IntegerField(read_only=True)
    position_total = serializers.IntegerField(read_only=True)
    department_headcount = DepartmentHeadcountSerializer(many=True, read_only=True)
    hire_trend = TrendPointSerializer(many=True, read_only=True)
    gender_distribution = DistributionPointSerializer(many=True, read_only=True)
    age_distribution = DistributionPointSerializer(many=True, read_only=True)


class SearchQuerySerializer(serializers.Serializer):
    q = serializers.CharField(max_length=100, allow_blank=False, trim_whitespace=True)


class SearchResultSerializer(serializers.Serializer):
    type = serializers.ChoiceField(choices=("employee", "department", "position"))
    id = serializers.UUIDField(read_only=True)
    title = serializers.CharField(read_only=True)
    subtitle = serializers.CharField(read_only=True)
