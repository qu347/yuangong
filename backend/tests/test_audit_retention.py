import json
from datetime import timedelta
from io import StringIO

import pytest
from django.core.management import call_command, get_commands
from django.test import override_settings
from django.utils import timezone

from modules.audit.models import AuditEvent


def create_event(label):
    return AuditEvent.objects.create(
        actor=None,
        action="create",
        resource_type="department",
        resource_id=label,
        resource_label=label,
        changes={},
        source="system",
    )


@pytest.mark.django_db
@override_settings(AUDIT_RETENTION_DAYS=0)
def test_retention_default_is_indefinite_and_never_reports_delete_candidates():
    create_event("RETENTION-0")
    output = StringIO()

    call_command("audit_retention_report", stdout=output)

    report = json.loads(output.getvalue())
    assert report["retention_days"] == 0
    assert report["automatic_deletion"] is False
    assert report["total_events"] == 1
    assert report["candidate_events"] == 0
    assert report["unarchived_candidates"] == 0
    assert "RETENTION-0" not in output.getvalue()


@pytest.mark.django_db
@override_settings(AUDIT_RETENTION_DAYS=30)
def test_retention_reports_old_archived_and_unarchived_counts(monkeypatch):
    from modules.audit.models import AuditArchiveBatch

    now = timezone.now()
    monkeypatch.setattr(timezone, "now", lambda: now - timedelta(days=60))
    old = create_event("OLD")
    monkeypatch.setattr(timezone, "now", lambda: now - timedelta(days=45))
    create_event("ARCHIVED-OLD")
    monkeypatch.setattr(timezone, "now", lambda: now)
    create_event("CURRENT")
    AuditArchiveBatch.objects.create(
        status=AuditArchiveBatch.Status.COMPLETED,
        cutoff_at=old.created_at + timedelta(days=1),
        first_event_at=old.created_at,
        last_event_at=old.created_at,
        event_count=1,
        archive_filename="safe.jsonl.gz",
        manifest_filename="safe.manifest.json",
        sha256="a" * 64,
        hmac_sha256="b" * 64,
        hmac_key_id="archive-v1",
        completed_at=now,
    )
    output = StringIO()

    call_command("audit_retention_report", stdout=output)

    report = json.loads(output.getvalue())
    assert report["candidate_events"] == 2
    assert report["completed_archives"] == 1
    assert report["unarchived_candidates"] == 1
    assert AuditEvent.objects.count() == 3


def test_no_audit_purge_command_exists():
    assert "purge_audit_events" not in get_commands()
