from django.core.exceptions import ValidationError
from django.core.mail import send_mail
from django.core.management.base import BaseCommand, CommandError
from django.core.validators import validate_email


class Command(BaseCommand):
    help = "Send a controlled SMTP configuration probe without account tokens."

    def add_arguments(self, parser):
        parser.add_argument("--to", required=True)
        parser.add_argument("--confirm", action="store_true")

    def handle(self, *args, **options):
        del args
        if not options["confirm"]:
            raise CommandError("Email probe requires explicit --confirm.")
        recipient = options["to"].strip().lower()
        try:
            validate_email(recipient)
        except ValidationError as error:
            raise CommandError("Email probe recipient is invalid.") from error
        if recipient.endswith(".invalid"):
            raise CommandError("Email probe cannot send to an .invalid address.")
        sent = send_mail(
            "Employee management SMTP probe",
            "This message verifies SMTP delivery only and contains no account code.",
            None,
            [recipient],
            fail_silently=False,
        )
        if sent != 1:
            raise CommandError("Email probe was not accepted by the configured backend.")
        self.stdout.write("probe_sent=1")
