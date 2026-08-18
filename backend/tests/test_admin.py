import pytest
from django.contrib import admin

from modules.employees.models import Employee
from modules.organizations.models import Department, Position


@pytest.mark.django_db
def test_directory_models_are_registered_in_django_admin():
    assert admin.site.is_registered(Department)
    assert admin.site.is_registered(Position)
    assert admin.site.is_registered(Employee)
