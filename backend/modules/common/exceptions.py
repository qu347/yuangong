from rest_framework import status
from rest_framework.exceptions import APIException
from rest_framework.response import Response
from rest_framework.views import exception_handler


class BusinessConflict(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "请求与当前资源状态冲突。"
    default_code = "resource_in_use"

    def __init__(self, detail=None, *, code=None):
        super().__init__(detail=detail, code=code or self.default_code)
        self.error_code = code or self.default_code


def api_exception_handler(exc, context):
    response = exception_handler(exc, context)
    if response is None:
        return None

    code_by_status = {
        status.HTTP_400_BAD_REQUEST: "validation_error",
        status.HTTP_401_UNAUTHORIZED: "authentication_failed",
        status.HTTP_403_FORBIDDEN: "permission_denied",
        status.HTTP_404_NOT_FOUND: "not_found",
        status.HTTP_405_METHOD_NOT_ALLOWED: "method_not_allowed",
        status.HTTP_409_CONFLICT: "resource_in_use",
    }
    message_by_status = {
        status.HTTP_400_BAD_REQUEST: "请求参数不正确。",
        status.HTTP_401_UNAUTHORIZED: "身份认证失败。",
        status.HTTP_403_FORBIDDEN: "当前账号没有执行该操作的权限。",
        status.HTTP_404_NOT_FOUND: "请求的资源不存在。",
        status.HTTP_405_METHOD_NOT_ALLOWED: "该资源不支持此请求方法。",
        status.HTTP_409_CONFLICT: "请求与当前资源状态冲突。",
    }
    request = context.get("request")
    request_id = request.headers.get("X-Request-ID") if request is not None else None

    return Response(
        {
            "code": getattr(
                exc, "error_code", code_by_status.get(response.status_code, "request_error")
            ),
            "message": message_by_status.get(response.status_code, "请求处理失败。"),
            "details": response.data,
            "request_id": request_id,
        },
        status=response.status_code,
    )
