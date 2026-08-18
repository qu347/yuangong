import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="AuditEvent",
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
                (
                    "action",
                    models.CharField(
                        choices=[
                            ("create", "创建"),
                            ("update", "更新"),
                            ("activate", "启用"),
                            ("deactivate", "停用"),
                            ("depart", "离职"),
                            ("reactivate", "恢复在职"),
                            ("account_deactivate", "账号停用"),
                            ("logout", "退出"),
                            ("logout_all", "退出全部会话"),
                        ],
                        max_length=32,
                    ),
                ),
                ("resource_type", models.CharField(max_length=64)),
                ("resource_id", models.CharField(max_length=128)),
                ("resource_label", models.CharField(blank=True, max_length=200)),
                ("changes", models.JSONField(blank=True, default=dict)),
                (
                    "source",
                    models.CharField(
                        choices=[
                            ("api", "API"),
                            ("admin", "管理后台"),
                            ("system", "系统"),
                        ],
                        max_length=16,
                    ),
                ),
                ("request_id", models.CharField(blank=True, max_length=64, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "actor",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="audit_events",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "verbose_name": "审计事件",
                "verbose_name_plural": "审计事件",
                "ordering": ["-created_at", "-id"],
                "indexes": [
                    models.Index(
                        fields=["resource_type", "resource_id"],
                        name="audit_audit_resourc_2ab5ff_idx",
                    ),
                    models.Index(
                        fields=["action", "created_at"],
                        name="audit_audit_action_0c0ad1_idx",
                    ),
                ],
            },
        ),
    ]
