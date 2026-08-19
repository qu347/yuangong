from django.utils.dateparse import parse_datetime
from rest_framework.exceptions import ValidationError

AUDIT_ORDERING_FIELDS = {"created_at", "-created_at", "action", "-action"}
AUDIT_EXACT_FILTERS = {
    "actor": "actor_id",
    "action": "action",
    "resource_type": "resource_type",
    "resource_id": "resource_id",
    "source": "source",
}


def apply_audit_filters(queryset, query_params):
    summary = {}
    for parameter, lookup in AUDIT_EXACT_FILTERS.items():
        value = query_params.get(parameter)
        if value:
            queryset = queryset.filter(**{lookup: value})
            summary[parameter] = value

    for parameter, lookup in (
        ("created_after", "created_at__gte"),
        ("created_before", "created_at__lte"),
    ):
        raw_value = query_params.get(parameter)
        if raw_value:
            parsed_value = parse_datetime(raw_value)
            if parsed_value is None:
                raise ValidationError({parameter: "必须是 ISO 8601 日期时间。"})
            queryset = queryset.filter(**{lookup: parsed_value})
            summary[parameter] = raw_value

    ordering = query_params.get("ordering", "-created_at")
    if ordering not in AUDIT_ORDERING_FIELDS:
        raise ValidationError({"ordering": "不支持该排序字段。"})
    if "ordering" in query_params:
        summary["ordering"] = ordering
    return queryset.order_by(ordering, "-id"), dict(sorted(summary.items()))
