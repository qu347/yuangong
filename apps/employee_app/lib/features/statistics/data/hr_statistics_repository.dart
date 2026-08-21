import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'hr_statistics.dart';

export 'hr_statistics.dart';

final hrStatisticsRepositoryProvider = Provider<HrStatisticsRepository>(
  (ref) => NetworkHrStatisticsRepository(ref.watch(apiClientProvider)),
);

abstract interface class HrStatisticsRepository {
  Future<HrStatistics> fetchStatistics();
}

class NetworkHrStatisticsRepository implements HrStatisticsRepository {
  const NetworkHrStatisticsRepository(this._client);

  final ApiClient _client;

  @override
  Future<HrStatistics> fetchStatistics() async {
    try {
      return HrStatistics.fromJson(
        await _client.getMap(ApiEndpoints.hrStatistics),
      );
    } on AppException catch (error) {
      throw switch (error.type) {
        AppExceptionType.network => const Failure.network(),
        AppExceptionType.unauthorized => const Failure.authentication(),
        AppExceptionType.forbidden => const Failure.permission(),
        AppExceptionType.validation => const Failure.validation(),
        AppExceptionType.conflict => const Failure.conflict(),
        AppExceptionType.protocol => const Failure.service(),
        AppExceptionType.unexpected => const Failure(
          type: FailureType.unexpected,
          message: '加载 HR 统计失败，请稍后重试。',
        ),
      };
    } on FormatException {
      throw const Failure.data();
    }
  }
}
