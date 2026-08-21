from django.urls import path

from .views import DashboardSummaryView, GlobalSearchView, HealthView, HrStatisticsView

app_name = "common"

urlpatterns = [
    path("health/", HealthView.as_view(), name="health"),
    path("dashboard/summary/", DashboardSummaryView.as_view(), name="dashboard-summary"),
    path("statistics/hr/", HrStatisticsView.as_view(), name="hr-statistics"),
    path("search/", GlobalSearchView.as_view(), name="global-search"),
]
