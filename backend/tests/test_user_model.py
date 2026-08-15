import uuid

import pytest

from modules.accounts.models import User


@pytest.mark.django_db
def test_user_uses_uuid_and_auditable_timestamps():
    """Catches a regression to integer IDs or missing audit timestamps."""
    user = User.objects.create_user(username="test_user", password="test-password-123")

    assert isinstance(user.pk, uuid.UUID)
    assert user.created_at is not None
    assert user.updated_at is not None
    assert user.is_active is True
