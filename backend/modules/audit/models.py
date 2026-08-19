import uuid

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


class AuditEventQuerySet(models.QuerySet):
    def update(self, **kwargs):
        if kwargs == {"actor": None} or kwargs == {"actor_id": None}:
            return super().update(**kwargs)
        raise ValidationError("审计事件不可修改。")

    def delete(self):
        raise ValidationError("审计事件不可删除。")


class AuditEvent(models.Model):
    class Action(models.TextChoices):
        CREATE = "create", "创建"
        UPDATE = "update", "更新"
        ACTIVATE = "activate", "启用"
        DEACTIVATE = "deactivate", "停用"
        DEPART = "depart", "离职"
        REACTIVATE = "reactivate", "恢复在职"
        ACCOUNT_DEACTIVATE = "account_deactivate", "账号停用"
        LOGOUT = "logout", "退出"
        LOGOUT_ALL = "logout_all", "退出全部会话"
        SESSION_REVOKED = "session_revoked", "会话撤销"
        OTHER_SESSIONS_REVOKED = "other_sessions_revoked", "其他会话撤销"
        ALL_SESSIONS_REVOKED = "all_sessions_revoked", "全部会话撤销"
        ACCOUNT_INVITATION_CREATED = "account_invitation_created", "账号邀请创建"
        ACCOUNT_INVITATION_RESENT = "account_invitation_resent", "账号邀请重发"
        ACCOUNT_INVITATION_REVOKED = "account_invitation_revoked", "账号邀请撤销"
        ACCOUNT_INVITATION_ACCEPTED = "account_invitation_accepted", "账号邀请接受"
        PASSWORD_CHANGED = "password_changed", "密码修改"
        PASSWORD_RESET_COMPLETED = "password_reset_completed", "密码重置完成"
        ACCOUNT_ACTIVATED = "account_activated", "账号恢复"
        ACCOUNT_ROLE_CHANGED = "account_role_changed", "账号角色变更"
        AUDIT_EXPORTED = "audit_exported", "审计导出"

    class Source(models.TextChoices):
        API = "api", "API"
        ADMIN = "admin", "管理后台"
        SYSTEM = "system", "系统"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="audit_events",
    )
    action = models.CharField(max_length=32, choices=Action.choices)
    resource_type = models.CharField(max_length=64)
    resource_id = models.CharField(max_length=128)
    resource_label = models.CharField(max_length=200, blank=True)
    changes = models.JSONField(default=dict, blank=True)
    source = models.CharField(max_length=16, choices=Source.choices)
    request_id = models.CharField(max_length=64, null=True, blank=True)  # noqa: DJ001
    created_at = models.DateTimeField(auto_now_add=True)

    objects = AuditEventQuerySet.as_manager()

    class Meta:
        ordering = ["-created_at", "-id"]
        indexes = [
            models.Index(fields=["resource_type", "resource_id"]),
            models.Index(fields=["action", "created_at"]),
        ]
        verbose_name = "审计事件"
        verbose_name_plural = "审计事件"
        permissions = [("export_auditevent", "Can export audit events")]

    def __str__(self):
        return f"{self.action}:{self.resource_type}:{self.resource_id}"

    def save(self, *args, **kwargs):
        if not self._state.adding:
            raise ValidationError("审计事件不可修改。")
        return super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        del args, kwargs
        raise ValidationError("审计事件不可删除。")
