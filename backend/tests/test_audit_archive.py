import gzip
import hashlib
import hmac
import io
import json
from datetime import timedelta
from uuid import UUID

import pytest
from django.core.management import CommandError, call_command
from django.test import override_settings
from django.utils import timezone

from modules.audit.models import AuditEvent

ARCHIVE_KEYS = {"audit-archive-test-v1": "test-only-archive-key-material"}


def create_events():
    first = AuditEvent.objects.create(
        actor=None,
        action="create",
        resource_type="department",
        resource_id="DEP-ARCHIVE-1",
        resource_label="虚构归档部门",
        changes={"name": {"to": "虚构归档部门"}},
        source="system",
    )
    second = AuditEvent.objects.create(
        actor=None,
        action="update",
        resource_type="employee",
        resource_id="EMP-ARCHIVE-2",
        resource_label="虚构归档员工",
        changes={"full_name": {"from": "旧", "to": "新"}},
        source="api",
    )
    return first, second


@pytest.mark.django_db
@override_settings(
    AUDIT_ARCHIVE_HMAC_ACTIVE_KID="audit-archive-test-v1",
    AUDIT_ARCHIVE_HMAC_KEYS=ARCHIVE_KEYS,
)
def test_archive_dry_run_reports_without_writing_files_or_batch(tmp_path):
    from modules.audit.archive import archive_events
    from modules.audit.models import AuditArchiveBatch

    create_events()
    before = AuditEvent.objects.count()

    result = archive_events(
        cutoff=timezone.now() + timedelta(minutes=1),
        output_dir=tmp_path,
        execute=False,
    )

    assert result.dry_run is True
    assert result.event_count == 2
    assert list(tmp_path.iterdir()) == []
    assert AuditArchiveBatch.objects.count() == 0
    assert AuditEvent.objects.count() == before


@pytest.mark.django_db
@override_settings(
    AUDIT_ARCHIVE_HMAC_ACTIVE_KID="audit-archive-test-v1",
    AUDIT_ARCHIVE_HMAC_KEYS=ARCHIVE_KEYS,
)
def test_archive_execute_writes_verified_manifest_without_deleting_events(tmp_path):
    from modules.audit.archive import archive_events, verify_archive
    from modules.audit.models import AuditArchiveBatch

    first, second = create_events()
    before = AuditEvent.objects.count()

    result = archive_events(
        cutoff=timezone.now() + timedelta(minutes=1),
        output_dir=tmp_path,
        execute=True,
        application_version="0.1.0",
        git_commit="a" * 40,
    )
    verified = verify_archive(result.manifest_path)
    manifest = json.loads(result.manifest_path.read_text(encoding="utf-8"))

    assert result.dry_run is False
    assert result.archive_path.exists()
    assert result.manifest_path.exists()
    assert verified["event_count"] == 2
    assert manifest["schema_version"] == 1
    assert manifest["hmac_algorithm"] == "HMAC-SHA256"
    assert manifest["hmac_key_id"] == "audit-archive-test-v1"
    assert "key" not in manifest
    assert manifest["git_commit"] == "a" * 40
    with gzip.open(result.archive_path, "rt", encoding="utf-8") as stream:
        rows = [json.loads(line) for line in stream]
    expected_ids = [
        str(event.id)
        for event in sorted((first, second), key=lambda item: (item.created_at, str(item.id)))
    ]
    assert [row["id"] for row in rows] == expected_ids
    assert AuditEvent.objects.count() == before
    batch = AuditArchiveBatch.objects.get(pk=result.batch_id)
    assert batch.status == AuditArchiveBatch.Status.COMPLETED
    assert batch.event_count == 2
    assert batch.archive_filename == result.archive_path.name


@pytest.mark.django_db
@override_settings(
    AUDIT_ARCHIVE_HMAC_ACTIVE_KID="audit-archive-test-v1",
    AUDIT_ARCHIVE_HMAC_KEYS=ARCHIVE_KEYS,
)
@pytest.mark.parametrize("mutation", ["byte", "truncate"])
def test_archive_verification_rejects_tampered_or_truncated_gzip(tmp_path, mutation):
    from modules.audit.archive import ArchiveVerificationError, archive_events, verify_archive

    create_events()
    result = archive_events(
        cutoff=timezone.now() + timedelta(minutes=1),
        output_dir=tmp_path,
        execute=True,
    )
    content = bytearray(result.archive_path.read_bytes())
    if mutation == "byte":
        content[len(content) // 2] ^= 1
    else:
        del content[-8:]
    result.archive_path.write_bytes(content)

    with pytest.raises(ArchiveVerificationError):
        verify_archive(result.manifest_path)


@pytest.mark.django_db
@override_settings(
    AUDIT_ARCHIVE_HMAC_ACTIVE_KID="audit-archive-test-v1",
    AUDIT_ARCHIVE_HMAC_KEYS=ARCHIVE_KEYS,
)
def test_archive_verification_rejects_wrong_key_and_modified_manifest(tmp_path):
    from modules.audit.archive import ArchiveVerificationError, archive_events, verify_archive

    create_events()
    result = archive_events(
        cutoff=timezone.now() + timedelta(minutes=1),
        output_dir=tmp_path,
        execute=True,
    )
    with override_settings(AUDIT_ARCHIVE_HMAC_KEYS={"audit-archive-test-v1": "wrong-key"}):
        with pytest.raises(ArchiveVerificationError):
            verify_archive(result.manifest_path)

    manifest = json.loads(result.manifest_path.read_text(encoding="utf-8"))
    manifest["event_count"] = 999
    result.manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(ArchiveVerificationError):
        verify_archive(result.manifest_path)


@pytest.mark.django_db
@override_settings(
    AUDIT_ARCHIVE_HMAC_ACTIVE_KID="audit-archive-test-v1",
    AUDIT_ARCHIVE_HMAC_KEYS=ARCHIVE_KEYS,
)
def test_archive_verification_rejects_duplicate_event_ids_with_valid_hmac(tmp_path):
    from modules.audit.archive import (
        ArchiveVerificationError,
        archive_events,
        canonical_manifest_bytes,
        verify_archive,
    )

    create_events()
    result = archive_events(
        cutoff=timezone.now() + timedelta(minutes=1),
        output_dir=tmp_path,
        execute=True,
    )
    with gzip.open(result.archive_path, "rt", encoding="utf-8") as stream:
        rows = [json.loads(line) for line in stream]
    rows.append(rows[0])
    with gzip.open(result.archive_path, "wt", encoding="utf-8", newline="\n") as stream:
        for row in rows:
            stream.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")
    manifest = json.loads(result.manifest_path.read_text(encoding="utf-8"))
    manifest["event_count"] = 3
    manifest["sha256"] = hashlib.sha256(result.archive_path.read_bytes()).hexdigest()
    unsigned = {key: value for key, value in manifest.items() if key != "hmac"}
    manifest["hmac"] = hmac.new(
        ARCHIVE_KEYS["audit-archive-test-v1"].encode(),
        canonical_manifest_bytes(unsigned),
        hashlib.sha256,
    ).hexdigest()
    result.manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, sort_keys=True), encoding="utf-8"
    )

    with pytest.raises(ArchiveVerificationError, match="duplicate"):
        verify_archive(result.manifest_path)


@pytest.mark.django_db
@override_settings(
    AUDIT_ARCHIVE_HMAC_ACTIVE_KID="audit-archive-test-v1",
    AUDIT_ARCHIVE_HMAC_KEYS=ARCHIVE_KEYS,
)
def test_archive_rejects_manifest_path_traversal_before_file_access(tmp_path):
    from modules.audit.archive import ArchiveVerificationError, archive_events, verify_archive

    create_events()
    result = archive_events(
        cutoff=timezone.now() + timedelta(minutes=1),
        output_dir=tmp_path,
        execute=True,
    )
    manifest = json.loads(result.manifest_path.read_text(encoding="utf-8"))
    manifest["archive_filename"] = "../outside.jsonl.gz"
    result.manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    with pytest.raises(ArchiveVerificationError, match="filename"):
        verify_archive(result.manifest_path)


@pytest.mark.django_db
@override_settings(
    AUDIT_ARCHIVE_HMAC_ACTIVE_KID="audit-archive-test-v1",
    AUDIT_ARCHIVE_HMAC_KEYS=ARCHIVE_KEYS,
)
def test_archive_refuses_existing_final_file_and_marks_batch_failed(tmp_path):
    from modules.audit.archive import ArchiveConflictError, archive_events, archive_filenames
    from modules.audit.models import AuditArchiveBatch

    first, second = create_events()
    batch_id = UUID("00000000-0000-0000-0000-000000000777")
    archive_name, _ = archive_filenames(batch_id, first.created_at, second.created_at)
    existing = tmp_path / archive_name
    existing.write_bytes(b"must-not-be-overwritten")

    with pytest.raises(ArchiveConflictError):
        archive_events(
            cutoff=timezone.now() + timedelta(minutes=1),
            output_dir=tmp_path,
            execute=True,
            batch_id=batch_id,
        )

    assert existing.read_bytes() == b"must-not-be-overwritten"
    batch = AuditArchiveBatch.objects.get(pk=batch_id)
    assert batch.status == AuditArchiveBatch.Status.FAILED
    assert batch.failure_code == "file_conflict"
    assert AuditEvent.objects.count() == 2


@pytest.mark.django_db
@override_settings(
    AUDIT_ARCHIVE_HMAC_ACTIVE_KID="missing-key",
    AUDIT_ARCHIVE_HMAC_KEYS={},
)
def test_archive_command_allows_dry_run_but_safely_rejects_execute_without_key(tmp_path):
    create_events()
    cutoff = (timezone.now() + timedelta(minutes=1)).isoformat()
    dry_output = io.StringIO()

    call_command(
        "archive_audit_events",
        before=cutoff,
        output_dir=str(tmp_path),
        dry_run=True,
        stdout=dry_output,
    )

    assert json.loads(dry_output.getvalue())["dry_run"] is True
    with pytest.raises(CommandError, match="key"):
        call_command(
            "archive_audit_events",
            before=cutoff,
            output_dir=str(tmp_path),
            execute=True,
        )
