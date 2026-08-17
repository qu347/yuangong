from drf_spectacular.utils import extend_schema
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from .serializers import CurrentUserSerializer, LoginSerializer


class LoginView(TokenObtainPairView):
    authentication_classes = []
    permission_classes = [AllowAny]
    serializer_class = LoginSerializer


class RefreshView(TokenRefreshView):
    authentication_classes = []
    permission_classes = [AllowAny]


class MeView(APIView):
    @extend_schema(responses=CurrentUserSerializer)
    def get(self, request):
        return Response(CurrentUserSerializer(request.user).data)
