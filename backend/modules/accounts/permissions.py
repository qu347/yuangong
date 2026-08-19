from rest_framework.permissions import BasePermission


class CanManageAccounts(BasePermission):
    message = "当前账号没有管理登录账号的权限。"

    def has_permission(self, request, view):
        del view
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.has_perm("accounts.change_user")
        )
