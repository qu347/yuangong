import uuid

from django.contrib.auth.models import AbstractUser
from django.db import models
from django.db.models import Q
from django.db.models.functions import Lower


def normalize_account_email(value):
    return (value or "").strip().lower()


class User(AbstractUser):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["username"]
        verbose_name = "用户"
        verbose_name_plural = "用户"
        constraints = [
            models.UniqueConstraint(
                Lower("email"),
                condition=~Q(email=""),
                name="accounts_user_email_ci_unique",
            )
        ]

    def clean(self):
        super().clean()
        self.email = normalize_account_email(self.email)

    def save(self, *args, **kwargs):
        self.email = normalize_account_email(self.email)
        return super().save(*args, **kwargs)


class AccountInvitation(models.Model):
    class TargetRole(models.TextChoices):
        EMPLOYEE = "employee", "员工"
        HR_ADMIN = "hr_admin", "HR 管理员"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    employee = models.ForeignKey(
        "employees.Employee",
        on_delete=models.PROTECT,
        related_name="account_invitations",
    )
    email = models.EmailField()
    username = models.CharField(max_length=150)
    target_role = models.CharField(max_length=32, choices=TargetRole.choices)
    token_digest = models.CharField(max_length=64, unique=True)
    expires_at = models.DateTimeField()
    accepted_at = models.DateTimeField(null=True, blank=True)
    revoked_at = models.DateTimeField(null=True, blank=True)
    created_by = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="created_account_invitations",
    )
    send_count = models.PositiveIntegerField(default=1)
    last_sent_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at", "-id"]
        constraints = [
            models.UniqueConstraint(
                fields=["employee"],
                condition=Q(accepted_at__isnull=True, revoked_at__isnull=True),
                name="accounts_one_open_invitation",
            )
        ]
        indexes = [
            models.Index(fields=["employee", "created_at"], name="acct_inv_emp_created_idx"),
            models.Index(fields=["expires_at"], name="acct_inv_expires_idx"),
        ]
        verbose_name = "账号邀请"
        verbose_name_plural = "账号邀请"

    def __str__(self):
        return f"{self.username}:{self.target_role}"

    def save(self, *args, **kwargs):
        self.email = normalize_account_email(self.email)
        self.username = self.username.strip()
        return super().save(*args, **kwargs)


class PasswordResetChallenge(models.Model):
    class RequestedFrom(models.TextChoices):
        APP = "app", "应用"
        SYSTEM = "system", "系统"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="password_reset_challenges",
    )
    token_digest = models.CharField(max_length=64, unique=True)
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(null=True, blank=True)
    revoked_at = models.DateTimeField(null=True, blank=True)
    requested_from = models.CharField(
        max_length=16,
        choices=RequestedFrom.choices,
        blank=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at", "-id"]
        constraints = [
            models.UniqueConstraint(
                fields=["user"],
                condition=Q(used_at__isnull=True, revoked_at__isnull=True),
                name="accounts_one_open_password_reset",
            )
        ]
        indexes = [models.Index(fields=["expires_at"], name="acct_reset_expires_idx")]
        verbose_name = "密码重置挑战"
        verbose_name_plural = "密码重置挑战"

    def __str__(self):
        return f"password-reset:{self.user_id}:{self.created_at}"


class AccountSession(models.Model):
    class ClientPlatform(models.TextChoices):
        WINDOWS = "windows", "Windows"
        ANDROID = "android", "Android"
        UNKNOWN = "unknown", "未知"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="account_sessions")
    created_at = models.DateTimeField(auto_now_add=True)
    last_seen_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    client_platform = models.CharField(
        max_length=16,
        choices=ClientPlatform.choices,
        default=ClientPlatform.UNKNOWN,
    )
    client_name = models.CharField(max_length=80, blank=True)
    app_version = models.CharField(max_length=32, blank=True)
    current_refresh_jti = models.CharField(max_length=255, blank=True)
    revoked_at = models.DateTimeField(null=True, blank=True)
    revoked_reason = models.CharField(max_length=32, blank=True)

    class Meta:
        ordering = ["-last_seen_at", "-created_at", "-id"]
        indexes = [
            models.Index(fields=["user", "revoked_at"], name="acct_sess_user_revoked_idx"),
            models.Index(fields=["expires_at"], name="acct_sess_expires_idx"),
        ]
        verbose_name = "账号会话"
        verbose_name_plural = "账号会话"

    def __str__(self):
        return f"{self.user_id}:{self.client_platform}:{self.id}"
