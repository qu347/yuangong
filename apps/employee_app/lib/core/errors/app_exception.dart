enum AppExceptionType { network, protocol, unexpected }

class AppException implements Exception {
  const AppException.network(this.message) : type = AppExceptionType.network;
  const AppException.protocol(this.message) : type = AppExceptionType.protocol;
  const AppException.unexpected(this.message) : type = AppExceptionType.unexpected;

  final AppExceptionType type;
  final String message;

  @override
  String toString() => 'AppException($type)';
}
