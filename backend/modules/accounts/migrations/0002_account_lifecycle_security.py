import uuid

import django.db.models.deletion
from django.db import migrations, models
from django.db.models import Q
from django.db.models.functions import Lower


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0001_initial"),
        ("employees", "0001_initial"),
    ]

    operations = [
        migrations.AddConstraint(
            model_name="user",
            constraint=models.UniqueConstraint(
                Lower("email"),
                condition=~Q(email=""),
                name="accounts_user_email_ci_unique",
            ),
        ),
        migrations.CreateModel(
            name="AccountInvitation",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid4,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("email", models.EmailField(max_length=254)),
                ("username", models.CharField(max_length=150)),
                (
                    "target_role",
                    models.CharField(
                        choices=[("employee", "员工"), ("hr_admin", "HR 管理员")],
                        max_length=32,
                    ),
                ),
                ("token_digest", models.CharField(max_length=64, unique=True)),
                ("expires_at", models.DateTimeField()),
                ("accepted_at", models.DateTimeField(blank=True, null=True)),
                ("revoked_at", models.DateTimeField(blank=True, null=True)),
                ("send_count", models.PositiveIntegerField(default=1)),
                ("last_sent_at", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "created_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="created_account_invitations",
                        to="accounts.user",
                    ),
                ),
                (
                    "employee",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="account_invitations",
                        to="employees.employee",
                    ),
                ),
            ],
            options={
                "verbose_name": "账号邀请",
                "verbose_name_plural": "账号邀请",
                "ordering": ["-created_at", "-id"],
                "indexes": [
                    models.Index(
                        fields=["employee", "created_at"],
                        name="acct_inv_emp_created_idx",
                    ),
                    models.Index(fields=["expires_at"], name="acct_inv_expires_idx"),
                ],
                "constraints": [
                    models.UniqueConstraint(
                        condition=Q(accepted_at__isnull=True, revoked_at__isnull=True),
                        fields=("employee",),
                        name="accounts_one_open_invitation",
                    )
                ],
            },
        ),
        migrations.CreateModel(
            name="PasswordResetChallenge",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid4,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("token_digest", models.CharField(max_length=64, unique=True)),
                ("expires_at", models.DateTimeField()),
                ("used_at", models.DateTimeField(blank=True, null=True)),
                ("revoked_at", models.DateTimeField(blank=True, null=True)),
                (
                    "requested_from",
                    models.CharField(
                        blank=True,
                        choices=[("app", "应用"), ("system", "系统")],
                        max_length=16,
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="password_reset_challenges",
                        to="accounts.user",
                    ),
                ),
            ],
            options={
                "verbose_name": "密码重置挑战",
                "verbose_name_plural": "密码重置挑战",
                "ordering": ["-created_at", "-id"],
                "indexes": [
                    models.Index(fields=["expires_at"], name="acct_reset_expires_idx")
                ],
                "constraints": [
                    models.UniqueConstraint(
                        condition=Q(revoked_at__isnull=True, used_at__isnull=True),
                        fields=("user",),
                        name="accounts_one_open_password_reset",
                    )
                ],
            },
        ),
        migrations.CreateModel(
            name="AccountSession",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid4,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("last_seen_at", models.DateTimeField(auto_now_add=True)),
                ("expires_at", models.DateTimeField()),
                (
                    "client_platform",
                    models.CharField(
                        choices=[
                            ("windows", "Windows"),
                            ("android", "Android"),
                            ("unknown", "未知"),
                        ],
                        default="unknown",
                        max_length=16,
                    ),
                ),
                ("client_name", models.CharField(blank=True, max_length=80)),
                ("app_version", models.CharField(blank=True, max_length=32)),
                ("current_refresh_jti", models.CharField(blank=True, max_length=255)),
                ("revoked_at", models.DateTimeField(blank=True, null=True)),
                ("revoked_reason", models.CharField(blank=True, max_length=32)),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="account_sessions",
                        to="accounts.user",
                    ),
                ),
            ],
            options={
                "verbose_name": "账号会话",
                "verbose_name_plural": "账号会话",
                "ordering": ["-last_seen_at", "-created_at", "-id"],
                "indexes": [
                    models.Index(
                        fields=["user", "revoked_at"],
                        name="acct_sess_user_revoked_idx",
                    ),
                    models.Index(fields=["expires_at"], name="acct_sess_expires_idx"),
                ],
            },
        ),
    ]
