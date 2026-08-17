from datetime import date

import pytest
from rest_framework.test import APIClient

from modules.accounts.models import User
from modules.employees.models import Employee
from modules.organizations.models import Department, Position


@pytest.fixture
def directory_data(db):
    engineering = Department.objects.create(
        code="ENG",
        name="研发中心",
        sort_order=10,
    )
    platform = Department.objects.create(
        code="ENG-PLATFORM",
        name="平台部",
        parent=engineering,
        sort_order=20,
    )
    hr = Department.objects.create(code="HR", name="人力资源部", sort_order=30)
    engineer = Position.objects.create(
        code="PLATFORM-SWE",
        name="软件工程师",
        department=platform,
    )
    partner = Position.objects.create(
        code="HR-BP",
        name="人力资源伙伴",
        department=hr,
    )
    employees = [
        Employee.objects.create(
            employee_no="EMP-0001",
            full_name="林知远",
            work_email="lin.zhiyuan@example.test",
            work_phone="010-5550-1001",
            department=platform,
            position=engineer,
            hire_date=date(2023, 5, 8),
        ),
        Employee.objects.create(
            employee_no="EMP-0002",
            full_name="周予安",
            work_email="zhou.yuan@example.test",
            work_phone="010-5550-1002",
            department=hr,
            position=partner,
            hire_date=date(2022, 9, 12),
        ),
        Employee.objects.create(
            employee_no="EMP-0003",
            full_name="许星河",
            work_email="xu.xinghe@example.test",
            department=platform,
            position=engineer,
            employment_status=Employee.EmploymentStatus.DEPARTED,
            hire_date=date(2021, 3, 15),
        ),
    ]
    return {
        "engineering": engineering,
        "platform": platform,
        "hr": hr,
        "engineer": engineer,
        "partner": partner,
        "employees": employees,
    }


@pytest.fixture
def authenticated_client(db):
    user = User.objects.create_user(username="directory_reader")
    client = APIClient()
    client.force_authenticate(user)
    return client


@pytest.mark.django_db
@pytest.mark.parametrize(
    "path",
    [
        "/api/v1/departments/",
        "/api/v1/positions/",
        "/api/v1/employees/",
    ],
)
def test_directory_lists_require_authentication(path):
    assert APIClient().get(path).status_code == 401


@pytest.mark.django_db
def test_department_and_position_lists_return_directory_safe_fields(
    authenticated_client,
    directory_data,
):
    departments = authenticated_client.get("/api/v1/departments/")
    positions = authenticated_client.get("/api/v1/positions/")

    assert departments.status_code == 200
    assert departments.json()[0] == {
        "id": str(directory_data["engineering"].id),
        "code": "ENG",
        "name": "研发中心",
        "parent": None,
        "status": "active",
        "sort_order": 10,
    }
    assert positions.status_code == 200
    assert positions.json()[0] == {
        "id": str(directory_data["engineer"].id),
        "code": "PLATFORM-SWE",
        "name": "软件工程师",
        "department": {
            "id": str(directory_data["platform"].id),
            "code": "ENG-PLATFORM",
            "name": "平台部",
        },
        "status": "active",
    }

    detail = authenticated_client.get(f"/api/v1/departments/{directory_data['platform'].id}/")
    assert detail.status_code == 200
    assert detail.json()["parent"] == str(directory_data["engineering"].id)
    assert (
        authenticated_client.get(
            "/api/v1/departments/00000000-0000-0000-0000-000000000000/"
        ).status_code
        == 404
    )


@pytest.mark.django_db
@pytest.mark.parametrize(
    "path",
    [
        "/api/v1/departments/",
        "/api/v1/positions/",
        "/api/v1/employees/",
    ],
)
def test_directory_endpoints_do_not_expose_write_methods(
    path,
    authenticated_client,
):
    assert authenticated_client.post(path, {}, format="json").status_code == 405


@pytest.mark.django_db
def test_employee_list_is_stably_paginated(authenticated_client, directory_data):
    response = authenticated_client.get("/api/v1/employees/?page=1&page_size=2")

    assert response.status_code == 200
    assert response.json()["count"] == 3
    assert response.json()["previous"] is None
    assert response.json()["next"] is not None
    assert [item["employee_no"] for item in response.json()["results"]] == [
        "EMP-0001",
        "EMP-0002",
    ]


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("search", "employee_no"),
    [
        ("林知", "EMP-0001"),
        ("EMP-0002", "EMP-0002"),
        ("XU.XINGHE@EXAMPLE.TEST", "EMP-0003"),
    ],
)
def test_employee_searches_name_number_and_work_email(
    search,
    employee_no,
    authenticated_client,
    directory_data,
):
    response = authenticated_client.get("/api/v1/employees/", {"search": search})

    assert response.status_code == 200
    assert [item["employee_no"] for item in response.json()["results"]] == [employee_no]


@pytest.mark.django_db
def test_employee_filters_department_and_employment_status(
    authenticated_client,
    directory_data,
):
    response = authenticated_client.get(
        "/api/v1/employees/",
        {
            "department": str(directory_data["platform"].id),
            "status": "active",
        },
    )

    assert response.status_code == 200
    assert [item["employee_no"] for item in response.json()["results"]] == ["EMP-0001"]


@pytest.mark.django_db
def test_employee_ordering_is_limited_and_applied(authenticated_client, directory_data):
    response = authenticated_client.get("/api/v1/employees/?ordering=-employee_no")

    assert response.status_code == 200
    assert [item["employee_no"] for item in response.json()["results"]] == [
        "EMP-0003",
        "EMP-0002",
        "EMP-0001",
    ]


@pytest.mark.django_db
@pytest.mark.parametrize(
    "query",
    [
        "department=not-a-uuid",
        "status=unknown",
        "page_size=0",
        "page_size=101",
    ],
)
def test_employee_list_rejects_invalid_filter_or_page_size(
    query,
    authenticated_client,
    directory_data,
):
    assert authenticated_client.get(f"/api/v1/employees/?{query}").status_code == 400


@pytest.mark.django_db
def test_employee_detail_returns_only_directory_fields(authenticated_client, directory_data):
    employee = directory_data["employees"][0]

    response = authenticated_client.get(f"/api/v1/employees/{employee.id}/")

    assert response.status_code == 200
    assert response.json() == {
        "id": str(employee.id),
        "employee_no": "EMP-0001",
        "full_name": "林知远",
        "work_email": "lin.zhiyuan@example.test",
        "work_phone": "010-5550-1001",
        "department": {
            "id": str(directory_data["platform"].id),
            "code": "ENG-PLATFORM",
            "name": "平台部",
        },
        "position": {
            "id": str(directory_data["engineer"].id),
            "code": "PLATFORM-SWE",
            "name": "软件工程师",
        },
        "employment_status": "active",
        "hire_date": "2023-05-08",
    }
    assert (
        authenticated_client.get(
            "/api/v1/employees/00000000-0000-0000-0000-000000000000/"
        ).status_code
        == 404
    )


@pytest.mark.django_db
def test_employee_list_avoids_related_object_n_plus_one(
    authenticated_client,
    directory_data,
    django_assert_num_queries,
):
    with django_assert_num_queries(2):
        response = authenticated_client.get("/api/v1/employees/")

    assert response.status_code == 200
    assert response.json()["count"] == 3
