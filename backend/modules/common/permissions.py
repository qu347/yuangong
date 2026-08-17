from rest_framework.permissions import SAFE_METHODS, BasePermission


class DirectoryModelPermission(BasePermission):
    message = "当前账号没有管理该目录资源的权限。"

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        if request.method in SAFE_METHODS:
            return True
        model = view.permission_model
        action = getattr(view, "permission_action", None)
        if action is None:
            action = "add" if request.method == "POST" else "change"
        permission = f"{model._meta.app_label}.{action}_{model._meta.model_name}"
        return bool(request.user and request.user.has_perm(permission))
