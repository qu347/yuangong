import pytest
from django.core.exceptions import ValidationError

from modules.accounts.models import User


@pytest.mark.parametrize(
    "password",
    [
        "Short8!",
        "1234567890123456",
        "password12345",
    ],
)
def test_account_password_policy_rejects_short_numeric_and_common_passwords(password):
    from modules.accounts.password_validation import validate_account_password

    user = User(username="password_policy_user", email="policy@example.invalid")

    with pytest.raises(ValidationError):
        validate_account_password(password, user=user, employee=None)


def test_account_password_policy_rejects_employee_context_similarity():
    from modules.accounts.password_validation import validate_account_password

    class EmployeeContext:
        full_name = "林安全"
        employee_no = "EMP-SEC-1001"

    user = User(username="secure.account", email="secure.account@example.invalid")

    with pytest.raises(ValidationError):
        validate_account_password(
            "EMP-SEC-1001-password!",
            user=user,
            employee=EmployeeContext(),
        )


def test_account_password_policy_accepts_a_strong_unrelated_password():
    from modules.accounts.password_validation import validate_account_password

    user = User(username="secure.account", email="secure.account@example.invalid")

    validate_account_password(
        "Aster!River7Cobalt",
        user=user,
        employee=None,
    )
