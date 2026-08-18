enum FailureType {
  network,
  authentication,
  permission,
  validation,
  conflict,
  service,
  data,
  unexpected,
}

class Failure implements Exception {
  const Failure({required this.type, required this.message});

  const Failure.network()
    : type = FailureType.network,
      message = '无法连接后端服务，请检查服务是否启动。';

  const Failure.service()
    : type = FailureType.service,
      message = '后端服务暂时不可用，请稍后重试。';

  const Failure.authentication([this.message = '登录状态已失效，请重新登录。'])
    : type = FailureType.authentication;

  const Failure.permission()
    : type = FailureType.permission,
      message = '当前账号没有权限执行此操作。';

  const Failure.validation([this.message = '请求参数不正确。'])
    : type = FailureType.validation;

  const Failure.conflict([this.message = '数据状态已发生变化，请重新加载后再试。'])
    : type = FailureType.conflict;

  const Failure.data() : type = FailureType.data, message = '后端返回了无法识别的数据。';

  final FailureType type;
  final String message;

  @override
  String toString() => message;
}
