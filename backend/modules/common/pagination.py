from rest_framework.exceptions import ValidationError
from rest_framework.pagination import PageNumberPagination


class DirectoryPagination(PageNumberPagination):
    page_size = 20
    page_size_query_param = "page_size"
    max_page_size = 100

    def get_page_size(self, request):
        value = request.query_params.get(self.page_size_query_param)
        if value is None:
            return self.page_size
        try:
            page_size = int(value)
        except (TypeError, ValueError) as error:
            raise ValidationError({"page_size": "page_size 必须是整数。"}) from error
        if not 1 <= page_size <= self.max_page_size:
            raise ValidationError({"page_size": "page_size 必须在 1 到 100 之间。"})
        return page_size
