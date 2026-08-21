from django.db.models import Count, F, Q
from django.db.models.functions import TruncMonth
from django.utils import timezone

from modules.audit.models import AuditEvent
from modules.employees.models import Employee
from modules.organizations.models import Department, Position


def dashboard_summary(user):
    employee_counts = Employee.objects.aggregate(
        employee_total=Count("id"),
        active_employee=Count("id", filter=Q(employment_status=Employee.EmploymentStatus.ACTIVE)),
        departed_employee=Count(
            "id", filter=Q(employment_status=Employee.EmploymentStatus.DEPARTED)
        ),
    )
    recent_operations = []
    if user.has_perm("audit.view_auditevent"):
        recent_operations = list(
            AuditEvent.objects.values(
                "id",
                "action",
                "resource_type",
                "resource_id",
                "resource_label",
                "created_at",
            )[:5]
        )
    return {
        **employee_counts,
        "department_total": Department.objects.count(),
        "position_total": Position.objects.count(),
        "recent_operations": recent_operations,
    }


def hr_statistics():
    department_headcount = list(
        Department.objects.annotate(count=Count("employees"))
        .order_by("sort_order", "code")
        .values("id", "name", "count")
    )
    for item in department_headcount:
        item["department_id"] = item.pop("id")
        item["department_name"] = item.pop("name")

    hire_trend = list(
        Employee.objects.exclude(hire_date__isnull=True)
        .annotate(month=TruncMonth("hire_date"))
        .values("month")
        .annotate(count=Count("id"))
        .order_by("month")
    )
    for item in hire_trend:
        item["month"] = item["month"].strftime("%Y-%m")

    gender_distribution = list(
        Employee.objects.exclude(gender=Employee.Gender.UNSPECIFIED)
        .values(label=F("gender"))
        .annotate(count=Count("id"))
        .order_by("gender")
    )
    today = timezone.localdate()

    def years_ago(years):
        try:
            return today.replace(year=today.year - years)
        except ValueError:
            return today.replace(year=today.year - years, day=28)

    age_counts = Employee.objects.exclude(birthday__isnull=True).aggregate(
        age_29_and_under=Count("id", filter=Q(birthday__gt=years_ago(30))),
        age_30_39=Count(
            "id",
            filter=Q(birthday__lte=years_ago(30), birthday__gt=years_ago(40)),
        ),
        age_40_49=Count(
            "id",
            filter=Q(birthday__lte=years_ago(40), birthday__gt=years_ago(50)),
        ),
        age_50_plus=Count("id", filter=Q(birthday__lte=years_ago(50))),
    )
    age_distribution = [
        {"label": label, "count": age_counts[key]}
        for key, label in (
            ("age_29_and_under", "29_and_under"),
            ("age_30_39", "30_39"),
            ("age_40_49", "40_49"),
            ("age_50_plus", "50_plus"),
        )
        if age_counts[key]
    ]

    return {
        "employee_total": Employee.objects.count(),
        "position_total": Position.objects.count(),
        "department_headcount": department_headcount,
        "hire_trend": hire_trend,
        "gender_distribution": gender_distribution,
        "age_distribution": age_distribution,
    }
