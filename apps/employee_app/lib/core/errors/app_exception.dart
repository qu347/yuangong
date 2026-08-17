enum AppExceptionType {
  network,
  unauthorized,
  forbidden,
  validation,
  conflict,
  protocol,
  unexpected,
}

class AppException implements Exception {
  const AppException.network(this.message) : type = AppExceptionType.network;
  const AppException.unauthorized(this.message)
    : type = AppExceptionType.unauthorized;
  const AppException.forbidden(this.message)
    : type = AppExceptionType.forbidden;
  const AppException.validation(this.message)
    : type = AppExceptionType.validation;
  const AppException.conflict(this.message) : type = AppExceptionType.conflict;
  const AppException.protocol(this.message) : type = AppExceptionType.protocol;
  const AppException.unexpected(this.message)
    : type = AppExceptionType.unexpected;

  final AppExceptionType type;
  final String message;

  @override
  String toString() => 'AppException($type)';
}
