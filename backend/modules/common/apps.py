from django.apps import AppConfig


class CommonConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "modules.common"
    verbose_name = "公共基础"

    def ready(self):
        from . import production_checks  # noqa: F401
