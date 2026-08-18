from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import AccountInvitation, AccountSession, PasswordResetChallenge, User

admin.site.register(User, UserAdmin)


class ReadOnlySecurityAdmin(admin.ModelAdmin):
    def has_add_permission(self, request):
        del request
        return False

    def has_change_permission(self, request, obj=None):
        del request, obj
        return False

    def has_delete_permission(self, request, obj=None):
        del request, obj
        return False


@admin.register(AccountInvitation)
class AccountInvitationAdmin(ReadOnlySecurityAdmin):
    list_display = ("username", "email", "target_role", "expires_at", "accepted_at", "revoked_at")
    fields = (
        "id",
        "employee",
        "email",
        "username",
        "target_role",
        "expires_at",
        "accepted_at",
        "revoked_at",
        "created_by",
        "send_count",
        "last_sent_at",
        "created_at",
        "updated_at",
    )
    readonly_fields = fields


@admin.register(PasswordResetChallenge)
class PasswordResetChallengeAdmin(ReadOnlySecurityAdmin):
    list_display = ("user", "expires_at", "used_at", "revoked_at", "requested_from", "created_at")
    fields = ("id", "user", "expires_at", "used_at", "revoked_at", "requested_from", "created_at")
    readonly_fields = fields


@admin.register(AccountSession)
class AccountSessionAdmin(ReadOnlySecurityAdmin):
    list_display = (
        "user",
        "client_platform",
        "client_name",
        "last_seen_at",
        "expires_at",
        "revoked_at",
    )
    fields = (
        "id",
        "user",
        "created_at",
        "last_seen_at",
        "expires_at",
        "client_platform",
        "client_name",
        "app_version",
        "revoked_at",
        "revoked_reason",
    )
    readonly_fields = fields
