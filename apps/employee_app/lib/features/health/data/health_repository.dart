import '../../../core/errors/app_exception.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'health_response.dart';

class HealthRepository {
  const HealthRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<HealthResponse> fetchHealth() async {
    try {
      final payload = await _apiClient.getMap(ApiEndpoints.health);
      return HealthResponse.fromJson(payload);
    } on AppException catch (error) {
      if (error.type == AppExceptionType.network) {
        throw const Failure.network();
      }
      throw const Failure.service();
    } on FormatException {
      throw const Failure.data();
    }
  }
}
