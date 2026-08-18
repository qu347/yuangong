from django.conf import settings
from django.contrib import admin
from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/", include("modules.common.urls")),
    path("api/v1/", include("modules.accounts.urls")),
    path("api/v1/", include("modules.organizations.urls")),
    path("api/v1/", include("modules.employees.urls")),
    path("api/v1/", include("modules.audit.urls")),
]

if settings.API_DOCS_ENABLED:
    urlpatterns += [
        path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
        path(
            "api/docs/",
            SpectacularSwaggerView.as_view(url_name="schema"),
            name="swagger-ui",
        ),
    ]
