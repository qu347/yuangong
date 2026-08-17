import os
from datetime import date

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from modules.accounts.models import User
from modules.accounts.rbac import sync_rbac_permissions
from modules.employees.models import Employee
from modules.organizations.models import Department, Position


class Command(BaseCommand):
    help = "创建或更新仅用于本地开发的虚构员工目录数据。"

    @transaction.atomic
    def handle(self, *args, **options):
        del args, options
        password = os.environ.get("EMPLOYEE_DEMO_PASSWORD")
        if not password:
            raise CommandError("必须通过进程环境变量 EMPLOYEE_DEMO_PASSWORD 提供演示密码。")

        groups = sync_rbac_permissions()

        department_specs = (
            ("HQ", "企业总部", None, 10),
            ("ENG", "研发中心", "HQ", 20),
            ("HR", "人力资源部", "HQ", 30),
            ("OPS", "运营中心", "HQ", 40),
        )
        departments = {}
        for code, name, parent_code, sort_order in department_specs:
            department, _ = Department.objects.update_or_create(
                code=code,
                defaults={
                    "name": name,
                    "parent": departments.get(parent_code),
                    "status": Department.Status.ACTIVE,
                    "sort_order": sort_order,
                },
            )
            departments[code] = department

        position_specs = (
            ("HQ-ADMIN", "行政专员", "HQ"),
            ("ENG-SWE", "软件工程师", "ENG"),
            ("ENG-QA", "质量工程师", "ENG"),
            ("HR-BP", "人力资源伙伴", "HR"),
            ("HR-REC", "招聘专员", "HR"),
            ("OPS-SPEC", "运营专员", "OPS"),
        )
        positions = {}
        for code, name, department_code in position_specs:
            position, _ = Position.objects.update_or_create(
                code=code,
                defaults={
                    "name": name,
                    "department": departments[department_code],
                    "status": Position.Status.ACTIVE,
                },
            )
            positions[code] = position

        user, _ = User.objects.update_or_create(
            username="demo.employee",
            defaults={
                "first_name": "林知远",
                "last_name": "",
                "email": "demo.employee@example.test",
                "is_active": True,
            },
        )
        user.set_password(password)
        user.save()
        user.groups.set([groups["employee"]])

        employee_specs = (
            (
                "EMP-0001",
                "林知远",
                "ENG",
                "ENG-SWE",
                "lin.zhiyuan",
                "1001",
                date(2023, 5, 8),
                "active",
            ),
            ("EMP-0002", "周予安", "HR", "HR-BP", "zhou.yuan", "1002", date(2022, 9, 12), "active"),
            (
                "EMP-0003",
                "许星河",
                "ENG",
                "ENG-QA",
                "xu.xinghe",
                "1003",
                date(2021, 3, 15),
                "departed",
            ),
            (
                "EMP-0004",
                "程嘉言",
                "OPS",
                "OPS-SPEC",
                "cheng.jiayan",
                "1004",
                date(2024, 2, 19),
                "active",
            ),
            (
                "EMP-0005",
                "沈明澈",
                "HQ",
                "HQ-ADMIN",
                "shen.mingche",
                "1005",
                date(2020, 7, 6),
                "active",
            ),
            (
                "EMP-0006",
                "顾清和",
                "ENG",
                "ENG-SWE",
                "gu.qinghe",
                "1006",
                date(2023, 11, 20),
                "active",
            ),
            (
                "EMP-0007",
                "陆景行",
                "HR",
                "HR-REC",
                "lu.jingxing",
                "1007",
                date(2024, 4, 8),
                "active",
            ),
            (
                "EMP-0008",
                "唐若川",
                "OPS",
                "OPS-SPEC",
                "tang.ruochuan",
                "1008",
                date(2022, 6, 13),
                "active",
            ),
            (
                "EMP-0009",
                "苏念初",
                "ENG",
                "ENG-SWE",
                "su.nianchu",
                "1009",
                date(2021, 12, 1),
                "active",
            ),
            (
                "EMP-0010",
                "叶书宁",
                "ENG",
                "ENG-QA",
                "ye.shuning",
                "1010",
                date(2023, 8, 28),
                "active",
            ),
            (
                "EMP-0011",
                "乔以安",
                "OPS",
                "OPS-SPEC",
                "qiao.yian",
                "1011",
                date(2020, 10, 19),
                "departed",
            ),
            ("EMP-0012", "温时雨", "HR", "HR-REC", "wen.shiyu", "1012", date(2024, 5, 6), "active"),
        )
        for (
            employee_no,
            full_name,
            department_code,
            position_code,
            email_name,
            phone_suffix,
            hire_date,
            status,
        ) in employee_specs:
            Employee.objects.update_or_create(
                employee_no=employee_no,
                defaults={
                    "full_name": full_name,
                    "work_email": f"{email_name}@example.test",
                    "work_phone": f"010-5550-{phone_suffix}",
                    "department": departments[department_code],
                    "position": positions[position_code],
                    "employment_status": status,
                    "hire_date": hire_date,
                    "user": user if employee_no == "EMP-0001" else None,
                },
            )

        self.stdout.write(self.style.SUCCESS("虚构演示数据已就绪：4 个部门、6 个岗位、12 名员工。"))
