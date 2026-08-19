import gzip
import hashlib
import hmac
import json
import os
import uuid
from dataclasses import dataclass
from datetime import UTC
from pathlib import Path

from django.conf import settings
from django.db.models import Max
from django.utils import timezone
from django.utils.dateparse import parse_datetime

from .keyrings import ArchiveKeyError, get_active_archive_key, get_archive_key
from .models import AuditArchiveBatch, AuditEvent


class ArchiveError(Exception):
    pass


class ArchiveConflictError(ArchiveError):
    pass


class ArchiveVerificationError(ArchiveError):
    pass


@dataclass(frozen=True)
class ArchiveResult:
    dry_run: bool
    event_count: int
    batch_id: uuid.UUID | None = None
    archive_path: Path | None = None
    manifest_path: Path | None = None


def _utc_iso(value):
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _compact_timestamp(value):
    return value.astimezone(UTC).strftime("%Y%m%dT%H%M%SZ")


def archive_filenames(batch_id, first_event_at, last_event_at):
    start = _compact_timestamp(first_event_at)
    end = _compact_timestamp(last_event_at)
    stem = f"audit-events-{start}-{end}-{batch_id}"
    return f"{stem}.jsonl.gz", f"{stem}.manifest.json"


def canonical_manifest_bytes(manifest):
    return json.dumps(
        manifest,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def _event_payload(event):
    return {
        "id": str(event.id),
        "created_at": _utc_iso(event.created_at),
        "actor_username": event.actor.username if event.actor is not None else "",
        "action": event.action,
        "resource_type": event.resource_type,
        "resource_id": event.resource_id,
        "resource_label": event.resource_label,
        "source": event.source,
        "request_id": event.request_id,
        "changes": event.changes,
    }


def _hash_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _resolve_output_dir(output_dir):
    path = Path(output_dir)
    if not path.is_absolute():
        raise ArchiveError("Archive output directory must be absolute.")
    resolved = path.resolve()
    repository_root = Path(settings.PROJECT_ROOT).resolve()
    if resolved == repository_root or repository_root in resolved.parents:
        raise ArchiveError("Archive output directory must be outside the repository.")
    resolved.mkdir(parents=True, exist_ok=True)
    return resolved


def _safe_failure_code(error):
    if isinstance(error, ArchiveConflictError):
        return "file_conflict"
    if isinstance(error, ArchiveKeyError):
        return "missing_key"
    if isinstance(error, ArchiveVerificationError):
        return "verification_failed"
    return "archive_failed"


def archive_events(
    *,
    cutoff,
    output_dir,
    execute=False,
    application_version="0.1.0",
    git_commit="unknown",
    batch_id=None,
):
    queryset = (
        AuditEvent.objects.select_related("actor")
        .filter(created_at__lt=cutoff)
        .order_by("created_at", "id")
    )
    event_count = queryset.count()
    first_event = queryset.first()
    last_event = queryset.last()
    if not execute:
        return ArchiveResult(dry_run=True, event_count=event_count)
    if first_event is None or last_event is None:
        raise ArchiveError("No audit events match the archive cutoff.")

    output_path = _resolve_output_dir(output_dir)
    key_id, key = get_active_archive_key()
    resolved_batch_id = batch_id or uuid.uuid4()
    batch = AuditArchiveBatch.objects.create(
        id=resolved_batch_id,
        status=AuditArchiveBatch.Status.PENDING,
        cutoff_at=cutoff,
        first_event_at=first_event.created_at,
        last_event_at=last_event.created_at,
        event_count=event_count,
        hmac_key_id=key_id,
    )
    archive_name, manifest_name = archive_filenames(
        batch.id, first_event.created_at, last_event.created_at
    )
    archive_path = output_path / archive_name
    manifest_path = output_path / manifest_name
    archive_temp = output_path / f".{batch.id}.archive.tmp"
    manifest_temp = output_path / f".{batch.id}.manifest.tmp"
    moved_archive = False
    try:
        if any(
            path.exists() for path in (archive_path, manifest_path, archive_temp, manifest_temp)
        ):
            raise ArchiveConflictError("Archive output already exists.")
        with archive_temp.open("xb") as raw_stream:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw_stream, mtime=0) as gzip_stream:
                for event in queryset.iterator(chunk_size=500):
                    line = json.dumps(
                        _event_payload(event),
                        ensure_ascii=False,
                        sort_keys=True,
                        separators=(",", ":"),
                    )
                    gzip_stream.write(line.encode("utf-8") + b"\n")
            raw_stream.flush()
            os.fsync(raw_stream.fileno())

        manifest = {
            "schema_version": 1,
            "batch_id": str(batch.id),
            "created_at": _utc_iso(batch.created_at),
            "cutoff_at": _utc_iso(cutoff),
            "first_event_at": _utc_iso(first_event.created_at),
            "last_event_at": _utc_iso(last_event.created_at),
            "event_count": event_count,
            "archive_filename": archive_name,
            "manifest_filename": manifest_name,
            "sha256": _hash_file(archive_temp),
            "hmac_algorithm": "HMAC-SHA256",
            "hmac_key_id": key_id,
            "application_version": application_version,
            "git_commit": git_commit,
        }
        manifest["hmac"] = hmac.new(
            key, canonical_manifest_bytes(manifest), hashlib.sha256
        ).hexdigest()
        with manifest_temp.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(manifest, stream, ensure_ascii=False, sort_keys=True, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())

        _verify_archive_payload(archive_temp, manifest)
        os.replace(archive_temp, archive_path)
        moved_archive = True
        os.replace(manifest_temp, manifest_path)
        batch.status = AuditArchiveBatch.Status.COMPLETED
        batch.archive_filename = archive_name
        batch.manifest_filename = manifest_name
        batch.sha256 = manifest["sha256"]
        batch.hmac_sha256 = manifest["hmac"]
        batch.completed_at = timezone.now()
        batch.save(
            update_fields=[
                "status",
                "archive_filename",
                "manifest_filename",
                "sha256",
                "hmac_sha256",
                "completed_at",
            ]
        )
        return ArchiveResult(
            dry_run=False,
            event_count=event_count,
            batch_id=batch.id,
            archive_path=archive_path,
            manifest_path=manifest_path,
        )
    except Exception as error:
        for path in (archive_temp, manifest_temp):
            if path.exists():
                path.unlink()
        if moved_archive and archive_path.exists() and not manifest_path.exists():
            archive_path.unlink()
        batch.status = AuditArchiveBatch.Status.FAILED
        batch.failure_code = _safe_failure_code(error)
        batch.save(update_fields=["status", "failure_code"])
        raise


def _parse_utc(value, field_name):
    parsed = parse_datetime(value) if isinstance(value, str) else None
    if parsed is None or parsed.tzinfo is None:
        raise ArchiveVerificationError(f"Invalid {field_name} timestamp.")
    return parsed.astimezone(UTC)


def _verify_archive_payload(archive_path, manifest):
    required = {
        "schema_version",
        "batch_id",
        "created_at",
        "cutoff_at",
        "first_event_at",
        "last_event_at",
        "event_count",
        "archive_filename",
        "manifest_filename",
        "sha256",
        "hmac_algorithm",
        "hmac_key_id",
        "hmac",
        "application_version",
        "git_commit",
    }
    if set(manifest) != required or manifest.get("schema_version") != 1:
        raise ArchiveVerificationError("Invalid archive manifest schema.")
    key = get_archive_key(manifest["hmac_key_id"])
    unsigned = {name: value for name, value in manifest.items() if name != "hmac"}
    expected_hmac = hmac.new(key, canonical_manifest_bytes(unsigned), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected_hmac, manifest["hmac"]):
        raise ArchiveVerificationError("Archive manifest HMAC mismatch.")
    if not hmac.compare_digest(_hash_file(archive_path), manifest["sha256"]):
        raise ArchiveVerificationError("Archive SHA-256 mismatch.")

    seen_ids = set()
    count = 0
    first_at = None
    last_at = None
    previous = None
    try:
        with gzip.open(archive_path, "rt", encoding="utf-8") as stream:
            for line in stream:
                row = json.loads(line)
                event_id = row.get("id")
                created_at = _parse_utc(row.get("created_at"), "event")
                if not isinstance(event_id, str):
                    raise ArchiveVerificationError("Archive event id is invalid.")
                if event_id in seen_ids:
                    raise ArchiveVerificationError("Archive contains duplicate event ids.")
                current = (created_at, event_id)
                if previous is not None and current < previous:
                    raise ArchiveVerificationError("Archive event ordering is invalid.")
                seen_ids.add(event_id)
                previous = current
                first_at = first_at or created_at
                last_at = created_at
                count += 1
    except ArchiveVerificationError:
        raise
    except (OSError, EOFError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ArchiveVerificationError("Archive gzip or JSONL is invalid.") from error

    if count != manifest["event_count"]:
        raise ArchiveVerificationError("Archive event count mismatch.")
    if first_at != _parse_utc(manifest["first_event_at"], "first_event_at"):
        raise ArchiveVerificationError("Archive first event time mismatch.")
    if last_at != _parse_utc(manifest["last_event_at"], "last_event_at"):
        raise ArchiveVerificationError("Archive last event time mismatch.")
    return {"event_count": count, "first_event_at": first_at, "last_event_at": last_at}


def verify_archive(manifest_path):
    path = Path(manifest_path).resolve()
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ArchiveVerificationError("Archive manifest is unreadable.") from error
    archive_name = manifest.get("archive_filename")
    if (
        not isinstance(archive_name, str)
        or Path(archive_name).name != archive_name
        or "/" in archive_name
        or "\\" in archive_name
    ):
        raise ArchiveVerificationError("Archive filename is unsafe.")
    archive_path = (path.parent / archive_name).resolve()
    if archive_path.parent != path.parent:
        raise ArchiveVerificationError("Archive filename escapes the manifest directory.")
    if not archive_path.is_file():
        raise ArchiveVerificationError("Archive file is missing.")
    return _verify_archive_payload(archive_path, manifest)


def retention_report():
    total = AuditEvent.objects.count()
    range_values = AuditEvent.objects.aggregate(
        earliest=Max("created_at"),
    )
    earliest = (
        AuditEvent.objects.order_by("created_at", "id").values_list("created_at", flat=True).first()
    )
    latest = range_values["earliest"]
    days = settings.AUDIT_RETENTION_DAYS
    candidate_count = 0
    unarchived_count = 0
    if days > 0:
        retention_cutoff = timezone.now() - timezone.timedelta(days=days)
        candidates = AuditEvent.objects.filter(created_at__lt=retention_cutoff)
        candidate_count = candidates.count()
        archived_cutoff = AuditArchiveBatch.objects.filter(
            status=AuditArchiveBatch.Status.COMPLETED
        ).aggregate(cutoff=Max("cutoff_at"))["cutoff"]
        if archived_cutoff is not None:
            candidates = candidates.filter(created_at__gte=archived_cutoff)
        unarchived_count = candidates.count()
    return {
        "retention_days": days,
        "automatic_deletion": False,
        "total_events": total,
        "earliest_event_at": _utc_iso(earliest) if earliest else None,
        "latest_event_at": _utc_iso(latest) if latest else None,
        "candidate_events": candidate_count,
        "completed_archives": AuditArchiveBatch.objects.filter(
            status=AuditArchiveBatch.Status.COMPLETED
        ).count(),
        "unarchived_candidates": unarchived_count,
    }
