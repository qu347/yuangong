import json

from django.core.management.base import BaseCommand

from modules.audit.archive import retention_report


class Command(BaseCommand):
    help = "Report audit retention and archive candidate counts without deleting events."

    def handle(self, *args, **options):
        del args, options
        self.stdout.write(json.dumps(retention_report(), sort_keys=True))
