from rest_framework import status
from rest_framework.exceptions import APIException


class AttachmentRequestError(APIException):
    status_code = status.HTTP_400_BAD_REQUEST

    def __init__(self, message, *, code):
        super().__init__(message, code=code)
        self.error_code = code


class AttachmentFileMissing(APIException):
    status_code = status.HTTP_404_NOT_FOUND
    default_detail = "附件文件不存在。"
    default_code = "attachment_file_missing"
    error_code = "attachment_file_missing"
