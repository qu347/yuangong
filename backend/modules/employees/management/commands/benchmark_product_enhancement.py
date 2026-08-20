import json
import statistics
import time
from io import StringIO

from django.contrib.auth.models import AnonymousUser
from django.core.management import call_command
from django.core.management.base import BaseCommand, CommandError

from modules.common.search import search_directory
from modules.common.services import dashboard_summary
from modules.employees.models import Employee
from modules.organizations.models import Department, Position

from .seed_performance_data import PREFIX


class Command(BaseCommand):
    help = "测量阶段五搜索、分页和 Dashboard 聚合耗时。"

    def add_arguments(self, parser):
        parser.add_argument("--skip-seed", action="store_true")
        parser.add_argument("--iterations", type=int, default=5)

    def handle(self, *args, **options):
        del args
        iterations = options["iterations"]
        if iterations < 1:
            raise CommandError("iterations must be positive.")
        if not options["skip_seed"]:
            call_command("seed_performance_data", stdout=StringIO())

        sample = (
            Employee.objects.filter(employee_no__startswith=PREFIX)
            .order_by("-employee_no")
            .values_list("employee_no", flat=True)
            .first()
        )
        if sample is None:
            raise CommandError("No performance employee data exists.")

        operations = {
            "search": lambda: search_directory(sample),
            "pagination": lambda: list(
                Employee.objects.select_related("department", "position").order_by("employee_no")[
                    :100
                ]
            ),
            "dashboard": lambda: dashboard_summary(AnonymousUser()),
        }
        for operation in operations.values():
            operation()
        milliseconds = {
            name: round(
                statistics.median(_measure(operation) for _ in range(iterations)),
                3,
            )
            for name, operation in operations.items()
        }
        dataset = {
            "departments": Department.objects.filter(code__startswith=f"{PREFIX}D").count(),
            "positions": Position.objects.filter(code__startswith=f"{PREFIX}P").count(),
            "employees": Employee.objects.filter(employee_no__startswith=PREFIX).count(),
        }
        payload = {
            "dataset": dataset,
            "iterations": iterations,
            "milliseconds": milliseconds,
            "targets_ms": {"search": 500, "pagination": 300, "dashboard": 500},
        }
        self.stdout.write(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        failed = [
            name for name, limit in payload["targets_ms"].items() if milliseconds[name] >= limit
        ]
        if failed:
            raise CommandError(f"Performance target exceeded: {', '.join(failed)}")


def _measure(operation):
    started = time.perf_counter()
    operation()
    return (time.perf_counter() - started) * 1000
