from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema
from rest_framework import generics
from rest_framework.response import Response
from rest_framework.views import APIView

from modules.common.pagination import DirectoryPagination

from .models import Notification
from .notification_serializers import NotificationSerializer


class NotificationListView(generics.ListAPIView):
    serializer_class = NotificationSerializer
    pagination_class = DirectoryPagination

    def get_queryset(self):
        return Notification.objects.filter(user=self.request.user)

    def list(self, request, *args, **kwargs):
        del args, kwargs
        queryset = self.get_queryset()
        unread_count = queryset.filter(read=False).count()
        page = self.paginate_queryset(queryset)
        response = self.get_paginated_response(self.get_serializer(page, many=True).data)
        response.data["unread_count"] = unread_count
        return response


class NotificationReadView(APIView):
    @extend_schema(request=None, responses=NotificationSerializer)
    def patch(self, request, notification_id):
        notification = get_object_or_404(
            Notification,
            pk=notification_id,
            user=request.user,
        )
        if not notification.read:
            notification.read = True
            notification.save(update_fields=["read"])
        return Response(NotificationSerializer(notification).data)
