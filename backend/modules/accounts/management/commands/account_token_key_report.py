import json

from django.conf import settings
from django.core.management.base import BaseCommand
from django.db.models import Count, Max
from django.utils import timezone

from modules.accounts.models import AccountInvitation, PasswordResetChallenge


def _counts_by_key(queryset):
    return {
        (row["token_key_id"] or "legacy"): row["count"]
        for row in queryset.values("token_key_id").annotate(count=Count("id")).order_by()
    }


class Command(BaseCommand):
    help = "Report active and legacy one-time token key ids without secrets or digests."

    def handle(self, *args, **options):
        del args, options
        now = timezone.now()
        invitations = AccountInvitation.objects.filter(
            accepted_at=None, revoked_at=None, expires_at__gt=now
        )
        resets = PasswordResetChallenge.objects.filter(
            used_at=None, revoked_at=None, expires_at__gt=now
        )
        latest_invitation = invitations.aggregate(value=Max("expires_at"))["value"]
        latest_reset = resets.aggregate(value=Max("expires_at"))["value"]
        latest = max(
            (value for value in (latest_invitation, latest_reset) if value is not None),
            default=None,
        )
        invitation_counts = _counts_by_key(invitations)
        reset_counts = _counts_by_key(resets)
        report = {
            "active_key_id": settings.ACCOUNT_TOKEN_HMAC_ACTIVE_KID,
            "valid_invitations_by_key": invitation_counts,
            "valid_resets_by_key": reset_counts,
            "legacy_count": invitation_counts.get("legacy", 0) + reset_counts.get("legacy", 0),
            "latest_expiration": latest.isoformat() if latest else None,
        }
        self.stdout.write(json.dumps(report, sort_keys=True))
