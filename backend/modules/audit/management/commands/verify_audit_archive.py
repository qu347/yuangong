import json

from django.core.management.base import BaseCommand, CommandError

from modules.audit.archive import ArchiveError, verify_archive
from modules.audit.keyrings import ArchiveKeyError


class Command(BaseCommand):
    help = "Verify archive filename, SHA-256, HMAC, gzip, JSONL, counts and time range."

    def add_arguments(self, parser):
        parser.add_argument("--manifest", required=True)

    def handle(self, *args, **options):
        del args
        try:
            result = verify_archive(options["manifest"])
        except (ArchiveError, ArchiveKeyError) as error:
            raise CommandError(str(error)) from error
        self.stdout.write(json.dumps({"verified": True, "event_count": result["event_count"]}))
