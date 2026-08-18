import pytest
from django.apps import apps
from django.core.exceptions import ValidationError

from modules.accounts.models import User


@pytest.mark.django_db
def test_audit_event_is_append_only_and_keeps_event_when_actor_is_deleted():
    AuditEvent = apps.get_model("audit", "AuditEvent")
    actor = User.objects.create_user(username="audit_actor")
    event = AuditEvent.objects.create(
        actor=actor,
        action="update",
        resource_type="employee",
        resource_id="EMP-0001",
        resource_label="虚构员工",
        changes={"full_name": {"from": "旧名称", "to": "新名称"}},
        source="api",
    )

    event.resource_label = "被修改的标签"
    with pytest.raises(ValidationError, match="审计事件不可修改"):
        event.save()
    with pytest.raises(ValidationError, match="审计事件不可删除"):
        event.delete()
    with pytest.raises(ValidationError, match="审计事件不可修改"):
        AuditEvent.objects.filter(pk=event.pk).update(resource_label="批量修改")
    with pytest.raises(ValidationError, match="审计事件不可删除"):
        AuditEvent.objects.filter(pk=event.pk).delete()

    actor.delete()
    event.refresh_from_db()
    assert event.actor is None
    assert event.resource_label == "虚构员工"
