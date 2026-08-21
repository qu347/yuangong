import json

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from modules.employees.models import Employee
from modules.organizations.models import Department, Position

PREFIX = "P5PERF-"


class Command(BaseCommand):
    help = "幂等追加虚构的阶段五性能数据；不会删除或修改既有目录数据。"

    def add_arguments(self, parser):
        parser.add_argument("--departments", type=int, default=100)
        parser.add_argument("--positions", type=int, default=500)
        parser.add_argument("--employees", type=int, default=10000)

    def handle(self, *args, **options):
        del args
        targets = {name: options[name] for name in ("departments", "positions", "employees")}
        if any(value < 1 for value in targets.values()):
            raise CommandError("Performance data counts must all be positive.")

        before = _counts()
        with transaction.atomic():
            Department.objects.bulk_create(
                [
                    Department(
                        code=f"{PREFIX}D{index:03d}",
                        name=f"性能测试部门{index:03d}",
                        sort_order=1000 + index,
                    )
                    for index in range(1, targets["departments"] + 1)
                ],
                ignore_conflicts=True,
                batch_size=500,
            )
            departments = list(
                Department.objects.filter(code__startswith=f"{PREFIX}D").order_by("code")
            )[: targets["departments"]]
            Position.objects.bulk_create(
                [
                    Position(
                        code=f"{PREFIX}P{index:04d}",
                        name=f"性能测试岗位{index:04d}",
                        department=departments[(index - 1) % len(departments)],
                    )
                    for index in range(1, targets["positions"] + 1)
                ],
                ignore_conflicts=True,
                batch_size=500,
            )
            positions = list(
                Position.objects.filter(code__startswith=f"{PREFIX}P")
                .select_related("department")
                .order_by("code")
            )[: targets["positions"]]
            Employee.objects.bulk_create(
                [
                    Employee(
                        employee_no=f"{PREFIX}{index:05d}",
                        full_name=f"性能测试员工{index:05d}",
                        work_email=f"p5perf{index:05d}@example.invalid",
                        department=positions[(index - 1) % len(positions)].department,
                        position=positions[(index - 1) % len(positions)],
                    )
                    for index in range(1, targets["employees"] + 1)
                ],
                ignore_conflicts=True,
                batch_size=1000,
            )

        after = _counts()
        payload = {
            **after,
            "created": {key: after[key] - before[key] for key in after},
            "non_destructive": True,
        }
        self.stdout.write(json.dumps(payload, ensure_ascii=False, sort_keys=True))


def _counts():
    return {
        "departments": Department.objects.filter(code__startswith=f"{PREFIX}D").count(),
        "positions": Position.objects.filter(code__startswith=f"{PREFIX}P").count(),
        "employees": Employee.objects.filter(employee_no__startswith=PREFIX).count(),
    }
