import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'dashboard_summary.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => NetworkDashboardRepository(ref.watch(apiClientProvider)),
);

abstract interface class DashboardRepository {
  Future<DashboardSummary> fetchSummary();
}

class NetworkDashboardRepository implements DashboardRepository {
  const NetworkDashboardRepository(this._client);
  final ApiClient _client;

  @override
  Future<DashboardSummary> fetchSummary() async {
    try {
      return DashboardSummary.fromJson(
        await _client.getMap(ApiEndpoints.dashboardSummary),
      );
    } on AppException catch (error) {
      throw error.type == AppExceptionType.network
          ? const Failure.network()
          : const Failure.service();
    } on FormatException {
      throw const Failure.data();
    }
  }
}
