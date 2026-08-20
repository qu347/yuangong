from django.db.models import Q

from modules.employees.models import Employee
from modules.organizations.models import Department, Position


def search_directory(query):
    employees = Employee.objects.select_related("department", "position").filter(
        Q(full_name__icontains=query)
        | Q(employee_no__icontains=query)
        | Q(work_email__icontains=query)
    )
    departments = Department.objects.filter(Q(name__icontains=query) | Q(code__icontains=query))
    positions = Position.objects.select_related("department").filter(
        Q(name__icontains=query) | Q(code__icontains=query)
    )

    results = [
        {
            "type": "employee",
            "id": employee.pk,
            "title": employee.full_name,
            "subtitle": " · ".join(
                part
                for part in (
                    employee.employee_no,
                    employee.work_email,
                    employee.department.name,
                    employee.position.name if employee.position else "",
                )
                if part
            ),
        }
        for employee in employees.order_by("employee_no")
    ]
    results.extend(
        {
            "type": "department",
            "id": department.pk,
            "title": department.name,
            "subtitle": department.code,
        }
        for department in departments.order_by("sort_order", "code")
    )
    results.extend(
        {
            "type": "position",
            "id": position.pk,
            "title": position.name,
            "subtitle": f"{position.code} · {position.department.name}",
        }
        for position in positions.order_by("department__sort_order", "name", "code")
    )
    return results
