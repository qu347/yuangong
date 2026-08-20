from datetime import date
from io import StringIO

import pytest
from django.apps import apps
from django.contrib.auth.models import Group
from django.core.exceptions import ValidationError
from django.core.management import call_command
from rest_framework.test import APIClient

from modules.accounts.models import User
from modules.audit.models import AuditEvent
from modules.employees.models import Employee
from modules.organizations.models import Department, Position


def authenticated_client(user):
    client = APIClient()
    client.force_authenticate(user)
    return client


def role_user(role):
    call_command("sync_rbac", stdout=StringIO())
    user = User.objects.create_user(username=f"phase5_{role}")
    user.groups.add(Group.objects.get(name=role))
    return user


@pytest.mark.django_db
def test_dashboard_requires_authentication_and_returns_aggregate_counts():
    department = Department.objects.create(code="P5-ENG", name="第五阶段研发")
    position = Position.objects.create(code="P5-SWE", name="工程师", department=department)
    Employee.objects.create(
        employee_no="P5-0001",
        full_name="林远",
        department=department,
        position=position,
    )
    Employee.objects.create(
        employee_no="P5-0002",
        full_name="周宁",
        department=department,
        employment_status=Employee.EmploymentStatus.DEPARTED,
    )
    user = role_user("employee")

    assert APIClient().get("/api/v1/dashboard/summary/").status_code == 401
    response = authenticated_client(user).get("/api/v1/dashboard/summary/")

    assert response.status_code == 200
    assert response.json() == {
        "employee_total": 2,
        "active_employee": 1,
        "departed_employee": 1,
        "department_total": 1,
        "position_total": 1,
        "recent_operations": [],
    }


@pytest.mark.django_db
def test_dashboard_is_stable_for_empty_data():
    user = role_user("employee")

    response = authenticated_client(user).get("/api/v1/dashboard/summary/")

    assert response.status_code == 200
    assert response.json()["employee_total"] == 0
    assert response.json()["active_employee"] == 0
    assert response.json()["department_total"] == 0


@pytest.mark.django_db
def test_dashboard_recent_operations_are_only_exposed_to_audit_readers():
    employee_user = role_user("employee")
    hr_user = role_user("hr_admin")
    AuditEvent.objects.create(
        actor=hr_user,
        action=AuditEvent.Action.CREATE,
        resource_type="employee",
        resource_id="safe-id",
        resource_label="P5-0001 · 林远",
        source=AuditEvent.Source.API,
    )

    employee_payload = authenticated_client(employee_user).get("/api/v1/dashboard/summary/").json()
    hr_payload = authenticated_client(hr_user).get("/api/v1/dashboard/summary/").json()

    assert employee_payload["recent_operations"] == []
    assert hr_payload["recent_operations"][0]["action"] == "create"
    assert hr_payload["recent_operations"][0]["resource_type"] == "employee"
    assert "changes" not in hr_payload["recent_operations"][0]


@pytest.mark.django_db
def test_hr_statistics_rejects_employee_and_returns_hand_checked_aggregates():
    engineering = Department.objects.create(code="P5-STAT-ENG", name="研发")
    hr = Department.objects.create(code="P5-STAT-HR", name="人事")
    Position.objects.create(code="P5-STAT-SWE", name="工程师", department=engineering)
    Position.objects.create(code="P5-STAT-HRBP", name="HRBP", department=hr)
    Employee.objects.create(
        employee_no="P5-STAT-1",
        full_name="甲",
        department=engineering,
        hire_date=date(2025, 1, 2),
    )
    Employee.objects.create(
        employee_no="P5-STAT-2",
        full_name="乙",
        department=engineering,
        hire_date=date(2025, 1, 20),
    )
    employee_user = role_user("employee")
    hr_user = role_user("hr_admin")

    assert authenticated_client(employee_user).get("/api/v1/statistics/hr/").status_code == 403
    response = authenticated_client(hr_user).get("/api/v1/statistics/hr/")

    assert response.status_code == 200
    assert response.json()["employee_total"] == 2
    assert response.json()["department_headcount"] == [
        {"department_id": str(engineering.id), "department_name": "研发", "count": 2},
        {"department_id": str(hr.id), "department_name": "人事", "count": 0},
    ]
    assert response.json()["position_total"] == 2
    assert response.json()["hire_trend"] == [{"month": "2025-01", "count": 2}]


@pytest.mark.django_db
def test_hr_statistics_only_aggregates_available_gender_and_age_data():
    department = Department.objects.create(code="P5-DEMO", name="数据部")
    Employee.objects.create(
        employee_no="P5-DEMO-1",
        full_name="甲",
        department=department,
        gender="female",
        birthday=date(2000, 1, 1),
    )
    Employee.objects.create(
        employee_no="P5-DEMO-2",
        full_name="乙",
        department=department,
        gender="male",
        birthday=date(1990, 1, 1),
    )
    Employee.objects.create(employee_no="P5-DEMO-3", full_name="丙", department=department)

    response = authenticated_client(role_user("hr_admin")).get("/api/v1/statistics/hr/")

    assert response.status_code == 200
    assert response.json()["gender_distribution"] == [
        {"label": "female", "count": 1},
        {"label": "male", "count": 1},
    ]
    assert response.json()["age_distribution"] == [
        {"label": "29_and_under", "count": 1},
        {"label": "30_39", "count": 1},
    ]


@pytest.mark.django_db
def test_department_tree_returns_counts_without_n_plus_one(django_assert_num_queries):
    root = Department.objects.create(code="P5-TREE", name="总部", sort_order=1)
    child = Department.objects.create(
        code="P5-TREE-ENG",
        name="研发部",
        parent=root,
        sort_order=2,
    )
    Employee.objects.create(employee_no="P5-TREE-1", full_name="甲", department=child)
    user = role_user("employee")
    client = authenticated_client(user)

    with django_assert_num_queries(1):
        response = client.get("/api/v1/departments/tree/")

    assert response.status_code == 200
    assert response.json() == [
        {
            "id": str(root.id),
            "code": "P5-TREE",
            "name": "总部",
            "status": "active",
            "employee_count": 0,
            "children": [
                {
                    "id": str(child.id),
                    "code": "P5-TREE-ENG",
                    "name": "研发部",
                    "status": "active",
                    "employee_count": 1,
                    "children": [],
                }
            ],
        }
    ]


@pytest.mark.django_db
def test_department_tree_returns_an_empty_list_without_departments():
    user = role_user("employee")

    response = authenticated_client(user).get("/api/v1/departments/tree/")

    assert response.status_code == 200
    assert response.json() == []


@pytest.mark.django_db
def test_employee_profile_fields_round_trip_and_manager_summary():
    department = Department.objects.create(code="P5-PROFILE", name="产品")
    manager = Employee.objects.create(
        employee_no="P5-MANAGER",
        full_name="直属负责人",
        department=department,
    )
    employee = Employee.objects.create(
        employee_no="P5-PROFILE-1",
        full_name="档案员工",
        department=department,
        avatar_url="https://assets.example.test/avatar.png",
        gender="female",
        birthday=date(1992, 6, 8),
        office_location="上海 A 座 8F",
        manager=manager,
        description="负责企业产品体验。",
    )
    user = role_user("employee")

    response = authenticated_client(user).get(f"/api/v1/employees/{employee.id}/")

    assert response.status_code == 200
    assert response.json()["avatar_url"] == "https://assets.example.test/avatar.png"
    assert response.json()["gender"] == "female"
    assert response.json()["birthday"] == "1992-06-08"
    assert response.json()["office_location"] == "上海 A 座 8F"
    assert response.json()["manager"] == {
        "id": str(manager.id),
        "employee_no": "P5-MANAGER",
        "full_name": "直属负责人",
    }
    assert response.json()["description"] == "负责企业产品体验。"


@pytest.mark.django_db
def test_employee_profile_rejects_insecure_avatar_and_manager_cycle():
    department = Department.objects.create(code="P5-CYCLE", name="循环校验")
    first = Employee.objects.create(employee_no="P5-CYCLE-1", full_name="甲", department=department)
    second = Employee.objects.create(
        employee_no="P5-CYCLE-2",
        full_name="乙",
        department=department,
        manager=first,
    )
    first.manager = second
    first.avatar_url = "http://insecure.example.test/avatar.png"

    with pytest.raises(ValidationError) as error:
        first.full_clean()

    assert "avatar_url" in error.value.message_dict
    assert "manager" in error.value.message_dict


@pytest.mark.django_db
def test_global_search_requires_query_and_returns_all_directory_types():
    department = Department.objects.create(code="P5-SEARCH", name="智能平台")
    position = Position.objects.create(
        code="P5-SEARCH-SWE", name="搜索工程师", department=department
    )
    employee = Employee.objects.create(
        employee_no="P5-SEARCH-001",
        full_name="搜索员工",
        work_email="search.person@example.test",
        department=department,
        position=position,
    )
    user = role_user("employee")
    client = authenticated_client(user)

    assert APIClient().get("/api/v1/search/?q=搜索").status_code == 401
    assert client.get("/api/v1/search/").status_code == 400
    response = client.get("/api/v1/search/?q=搜索&page=1&page_size=2")

    assert response.status_code == 200
    assert response.json()["count"] == 2
    assert response.json()["next"] is None
    assert response.json()["results"] == [
        {
            "type": "employee",
            "id": str(employee.id),
            "title": "搜索员工",
            "subtitle": ("P5-SEARCH-001 · search.person@example.test · 智能平台 · 搜索工程师"),
        },
        {
            "type": "position",
            "id": str(position.id),
            "title": "搜索工程师",
            "subtitle": "P5-SEARCH-SWE · 智能平台",
        },
    ]
    assert client.get("/api/v1/search/?q=搜索&page_size=51").status_code == 400


@pytest.mark.django_db
def test_global_search_matches_employee_number_email_and_department_name():
    department = Department.objects.create(code="P5-FIND", name="客户成功")
    employee = Employee.objects.create(
        employee_no="P5-FIND-001",
        full_name="顾问",
        work_email="advisor@example.test",
        department=department,
    )
    client = authenticated_client(role_user("employee"))

    for query in ("P5-FIND-001", "ADVISOR@EXAMPLE.TEST"):
        response = client.get("/api/v1/search/", {"q": query})
        assert response.status_code == 200
        assert response.json()["results"][0]["id"] == str(employee.id)

    department_response = client.get("/api/v1/search/", {"q": "客户成功"})
    assert department_response.json()["results"][0]["type"] == "department"


@pytest.mark.django_db
def test_notifications_are_paginated_owner_only_and_mark_read_idempotently():
    notification_model = apps.get_model("accounts", "Notification")
    owner = User.objects.create_user(username="phase5_notice_owner")
    other = User.objects.create_user(username="phase5_notice_other")
    first = notification_model.objects.create(
        user=owner,
        title="账号变化",
        content="你的账号资料已更新。",
    )
    notification_model.objects.create(user=owner, title="系统通知", content="系统维护完成。")
    foreign = notification_model.objects.create(user=other, title="私有通知", content="不可见。")
    client = authenticated_client(owner)

    assert APIClient().get("/api/v1/notifications/").status_code == 401
    response = client.get("/api/v1/notifications/?page=1&page_size=1")

    assert response.status_code == 200
    assert response.json()["count"] == 2
    assert response.json()["unread_count"] == 2
    assert len(response.json()["results"]) == 1
    assert client.patch(f"/api/v1/notifications/{foreign.id}/read/").status_code == 404

    first_read = client.patch(f"/api/v1/notifications/{first.id}/read/")
    second_read = client.patch(f"/api/v1/notifications/{first.id}/read/")
    assert first_read.status_code == 200
    assert second_read.status_code == 200
    assert first_read.json()["read"] is True
    assert client.get("/api/v1/notifications/").json()["unread_count"] == 1
