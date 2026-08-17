from django.urls import path

from .views import AuditEventDetailView, AuditEventListView

app_name = "audit"

urlpatterns = [
    path("audit-events/", AuditEventListView.as_view(), name="audit-event-list"),
    path(
        "audit-events/<uuid:pk>/",
        AuditEventDetailView.as_view(),
        name="audit-event-detail",
    ),
]
