import csv
import io
import json
from datetime import UTC

AUDIT_CSV_FIELDS = (
    "created_at",
    "actor_username",
    "action",
    "resource_type",
    "resource_id",
    "resource_label",
    "source",
    "request_id",
    "changes",
)
UNSAFE_CSV_PREFIXES = ("=", "+", "-", "@", "\t", "\r", "\n")


def sanitize_csv_text(value):
    text = "" if value is None else str(value)
    return f"'{text}" if text.startswith(UNSAFE_CSV_PREFIXES) else text


def _utc_iso(value):
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def build_audit_csv(events):
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=AUDIT_CSV_FIELDS, lineterminator="\r\n")
    writer.writeheader()
    for event in events:
        writer.writerow(
            {
                "created_at": _utc_iso(event.created_at),
                "actor_username": sanitize_csv_text(
                    event.actor.username if event.actor is not None else ""
                ),
                "action": sanitize_csv_text(event.action),
                "resource_type": sanitize_csv_text(event.resource_type),
                "resource_id": sanitize_csv_text(event.resource_id),
                "resource_label": sanitize_csv_text(event.resource_label),
                "source": sanitize_csv_text(event.source),
                "request_id": sanitize_csv_text(event.request_id),
                "changes": sanitize_csv_text(
                    json.dumps(
                        event.changes,
                        ensure_ascii=False,
                        sort_keys=True,
                        separators=(",", ":"),
                    )
                ),
            }
        )
    return stream.getvalue().encode("utf-8-sig")
