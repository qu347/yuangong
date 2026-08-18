from django.core.management.base import BaseCommand

from modules.accounts.rbac import sync_rbac_permissions


class Command(BaseCommand):
    help = "幂等同步员工管理系统的固定角色与 Django model permissions。"

    def handle(self, *args, **options):
        del args, options
        sync_rbac_permissions()
        self.stdout.write(self.style.SUCCESS("RBAC 角色与权限已同步。"))
