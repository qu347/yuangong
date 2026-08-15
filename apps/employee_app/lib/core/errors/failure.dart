enum FailureType { network, service, data, unexpected }

class Failure implements Exception {
  const Failure({required this.type, required this.message});

  const Failure.network()
      : type = FailureType.network,
        message = '无法连接后端服务，请检查服务是否启动。';

  const Failure.service()
      : type = FailureType.service,
        message = '后端服务暂时不可用，请稍后重试。';

  const Failure.data()
      : type = FailureType.data,
        message = '后端返回了无法识别的数据。';

  final FailureType type;
  final String message;

  @override
  String toString() => message;
}
