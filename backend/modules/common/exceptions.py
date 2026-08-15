from rest_framework.response import Response
from rest_framework.views import exception_handler


def api_exception_handler(exc, context):
    response = exception_handler(exc, context)
    if response is None:
        return None

    message = "请求处理失败"
    details = response.data
    if response.status_code == 400:
        message = "请求参数不正确"

    return Response(
        {
            "code": "VALIDATION_ERROR" if response.status_code == 400 else "REQUEST_ERROR",
            "message": message,
            "details": details,
            "request_id": None,
        },
        status=response.status_code,
    )
