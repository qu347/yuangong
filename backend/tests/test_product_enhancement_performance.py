import json
from io import StringIO

import pytest
from django.core.management import call_command

from modules.employees.models import Employee
from modules.organizations.models import Department


@pytest.mark.django_db
def test_performance_seed_is_idempotent_and_preserves_existing_directory_data():
    existing_department = Department.objects.create(code="KEEP", name="必须保留")
    existing = Employee.objects.create(
        employee_no="KEEP-001",
        full_name="既有员工",
        department=existing_department,
    )

    first_output = StringIO()
    second_output = StringIO()
    call_command(
        "seed_performance_data",
        departments=5,
        positions=10,
        employees=20,
        stdout=first_output,
    )
    call_command(
        "seed_performance_data",
        departments=5,
        positions=10,
        employees=20,
        stdout=second_output,
    )

    assert Employee.objects.filter(pk=existing.pk, full_name="既有员工").exists()
    assert Employee.objects.filter(employee_no__startswith="P5PERF-").count() == 20
    assert json.loads(first_output.getvalue())["employees"] == 20
    assert json.loads(second_output.getvalue())["created"]["employees"] == 0


@pytest.mark.django_db
def test_benchmark_reports_search_pagination_and_dashboard_timings():
    call_command("seed_performance_data", departments=5, positions=10, employees=20)
    output = StringIO()

    call_command(
        "benchmark_product_enhancement",
        skip_seed=True,
        iterations=2,
        stdout=output,
    )

    payload = json.loads(output.getvalue())
    assert payload["dataset"] == {"departments": 5, "positions": 10, "employees": 20}
    assert set(payload["milliseconds"]) == {"search", "pagination", "dashboard"}
    assert all(value >= 0 for value in payload["milliseconds"].values())


@pytest.mark.django_db
def test_realistic_ten_thousand_employee_dataset_meets_phase_five_targets():
    call_command("seed_performance_data")
    output = StringIO()

    call_command(
        "benchmark_product_enhancement",
        skip_seed=True,
        iterations=3,
        stdout=output,
    )

    payload = json.loads(output.getvalue())
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    assert payload["dataset"] == {
        "departments": 100,
        "positions": 500,
        "employees": 10000,
    }
    assert payload["milliseconds"]["search"] < 500
    assert payload["milliseconds"]["pagination"] < 300
    assert payload["milliseconds"]["dashboard"] < 500
