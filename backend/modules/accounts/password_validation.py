import re
from difflib import SequenceMatcher

from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError


def _normalized(value):
    return re.sub(r"\W+", "", (value or "").casefold())


def validate_account_password(password, *, user, employee):
    validate_password(password, user=user)
    normalized_password = _normalized(password)
    context_values = [user.username, user.email]
    if employee is not None:
        context_values.extend([employee.full_name, employee.employee_no])
    for value in context_values:
        normalized_value = _normalized(value)
        if len(normalized_value) < 3:
            continue
        if (
            normalized_value in normalized_password
            or SequenceMatcher(None, normalized_password, normalized_value).quick_ratio() >= 0.7
        ):
            raise ValidationError("密码与账号或员工信息过于相似。", code="password_too_similar")
