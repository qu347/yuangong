from django.urls import path

from .account_views import (
    AccountActivateView,
    AccountDeactivateView,
    AccountDetailView,
    AccountListView,
    AccountRevokeSessionsView,
    AccountRoleChangeView,
)
from .invitation_views import (
    InvitationAcceptView,
    InvitationDetailView,
    InvitationListCreateView,
    InvitationResendView,
    InvitationRevokeView,
)
from .password_views import PasswordChangeView, PasswordResetConfirmView, PasswordResetRequestView
from .session_views import RevokeOtherSessionsView, SessionListView, SessionRevokeView
from .views import LoginView, LogoutAllView, LogoutView, MeView, RefreshView

app_name = "accounts"

urlpatterns = [
    path("auth/login/", LoginView.as_view(), name="login"),
    path("auth/refresh/", RefreshView.as_view(), name="refresh"),
    path("auth/logout/", LogoutView.as_view(), name="logout"),
    path("auth/logout-all/", LogoutAllView.as_view(), name="logout-all"),
    path("auth/sessions/", SessionListView.as_view(), name="session-list"),
    path(
        "auth/sessions/<uuid:session_id>/revoke/",
        SessionRevokeView.as_view(),
        name="session-revoke",
    ),
    path(
        "auth/sessions/revoke-others/",
        RevokeOtherSessionsView.as_view(),
        name="session-revoke-others",
    ),
    path("accounts/invitations/", InvitationListCreateView.as_view(), name="invitation-list"),
    path("accounts/", AccountListView.as_view(), name="account-list"),
    path("accounts/<uuid:account_id>/", AccountDetailView.as_view(), name="account-detail"),
    path(
        "accounts/<uuid:account_id>/activate/",
        AccountActivateView.as_view(),
        name="account-activate",
    ),
    path(
        "accounts/<uuid:account_id>/deactivate/",
        AccountDeactivateView.as_view(),
        name="account-deactivate",
    ),
    path(
        "accounts/<uuid:account_id>/change-role/",
        AccountRoleChangeView.as_view(),
        name="account-change-role",
    ),
    path(
        "accounts/<uuid:account_id>/revoke-sessions/",
        AccountRevokeSessionsView.as_view(),
        name="account-revoke-sessions",
    ),
    path(
        "accounts/invitations/<uuid:invitation_id>/",
        InvitationDetailView.as_view(),
        name="invitation-detail",
    ),
    path(
        "accounts/invitations/<uuid:invitation_id>/resend/",
        InvitationResendView.as_view(),
        name="invitation-resend",
    ),
    path(
        "accounts/invitations/<uuid:invitation_id>/revoke/",
        InvitationRevokeView.as_view(),
        name="invitation-revoke",
    ),
    path("auth/invitations/accept/", InvitationAcceptView.as_view(), name="invitation-accept"),
    path(
        "auth/password-reset/request/",
        PasswordResetRequestView.as_view(),
        name="password-reset-request",
    ),
    path(
        "auth/password-reset/confirm/",
        PasswordResetConfirmView.as_view(),
        name="password-reset-confirm",
    ),
    path("auth/password/change/", PasswordChangeView.as_view(), name="password-change"),
    path("me/", MeView.as_view(), name="me"),
]
