import json
from datetime import UTC

from django.core.management.base import BaseCommand, CommandError
from django.utils.dateparse import parse_datetime

from modules.audit.archive import ArchiveError, archive_events
from modules.audit.keyrings import ArchiveKeyError


class Command(BaseCommand):
    help = "Create a verifiable, non-destructive audit archive; defaults to dry-run."

    def add_arguments(self, parser):
        parser.add_argument("--before", required=True)
        parser.add_argument("--output-dir", required=True)
        parser.add_argument("--execute", action="store_true")
        parser.add_argument("--dry-run", action="store_true")
        parser.add_argument("--application-version", default="0.1.0")
        parser.add_argument("--git-commit", default="unknown")

    def handle(self, *args, **options):
        del args
        if options["execute"] and options["dry_run"]:
            raise CommandError("--execute and --dry-run are mutually exclusive.")
        cutoff = parse_datetime(options["before"])
        if cutoff is None or cutoff.tzinfo is None:
            raise CommandError("--before must be an ISO 8601 timezone-aware datetime.")
        try:
            result = archive_events(
                cutoff=cutoff.astimezone(UTC),
                output_dir=options["output_dir"],
                execute=options["execute"],
                application_version=options["application_version"],
                git_commit=options["git_commit"],
            )
        except (ArchiveError, ArchiveKeyError) as error:
            raise CommandError(str(error)) from error
        payload = {
            "dry_run": result.dry_run,
            "event_count": result.event_count,
            "batch_id": str(result.batch_id) if result.batch_id else None,
            "archive_filename": result.archive_path.name if result.archive_path else None,
            "manifest_filename": result.manifest_path.name if result.manifest_path else None,
        }
        self.stdout.write(json.dumps(payload, sort_keys=True))
