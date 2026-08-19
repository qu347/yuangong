from django.db import transaction
from django.utils import timezone
from drf_spectacular.utils import extend_schema
from rest_framework import status
from rest_framework.exceptions import NotFound
from rest_framework.response import Response
from rest_framework.views import APIView

from modules.audit.services import record_audit_event

from .models import AccountSession
from .session_serializers import (
    AccountSessionSerializer,
    SessionCountResponseSerializer,
    SessionRevokeResponseSerializer,
)
from .sessions import revoke_all_account_sessions, revoke_session


class SessionListView(APIView):
    @extend_schema(responses=AccountSessionSerializer(many=True))
    def get(self, request):
        sessions = AccountSession.objects.filter(
            user=request.user,
            revoked_at=None,
            expires_at__gt=timezone.now(),
        ).order_by("-last_seen_at", "-created_at", "-id")
        return Response(
            AccountSessionSerializer(
                sessions,
                many=True,
                context={"current_sid": request.auth.get("sid")},
            ).data
        )


class SessionRevokeView(APIView):
    @extend_schema(request=None, responses=SessionRevokeResponseSerializer)
    def post(self, request, session_id):
        session = AccountSession.objects.filter(pk=session_id, user=request.user).first()
        if session is None:
            raise NotFound()
        current_sid = str(request.auth.get("sid"))
        is_current = str(session.id) == current_sid
        with transaction.atomic():
            changed = revoke_session(session, reason="user_revoked")
            if changed:
                record_audit_event(
                    actor=request.user,
                    action="session_revoked",
                    resource_type="account_session",
                    resource_id=session.id,
                    resource_label=session.client_platform,
                    changes={
                        "session_id": {"to": str(session.id)},
                        "client_platform": {"to": session.client_platform},
                        "revoked_reason": {"to": "user_revoked"},
                    },
                    source="api",
                    request_id=request.headers.get("X-Request-ID"),
                )
        return Response({"changed": changed, "is_current": is_current})


class RevokeOtherSessionsView(APIView):
    @extend_schema(request=None, responses=SessionCountResponseSerializer)
    def post(self, request):
        current_sid = request.auth.get("sid")
        with transaction.atomic():
            revoked = revoke_all_account_sessions(
                request.user,
                reason="other_sessions_revoked",
                exclude_sid=current_sid,
            )
            if revoked:
                record_audit_event(
                    actor=request.user,
                    action="other_sessions_revoked",
                    resource_type="user",
                    resource_id=request.user.pk,
                    resource_label=request.user.username,
                    changes={"revoked_sessions": {"to": revoked}},
                    source="api",
                    request_id=request.headers.get("X-Request-ID"),
                )
        return Response({"revoked_sessions": revoked}, status=status.HTTP_200_OK)
