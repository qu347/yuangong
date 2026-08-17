import 'package:employee_app/core/errors/app_exception.dart';
import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/core/network/api_endpoints.dart';
import 'package:employee_app/features/health/data/health_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient apiClient;
  late HealthRepository repository;

  setUp(() {
    apiClient = MockApiClient();
    repository = HealthRepository(apiClient);
  });

  test('maps the complete health payload into a response', () async {
    when(() => apiClient.getMap(ApiEndpoints.health)).thenAnswer(
      (_) async => <String, dynamic>{
        'status': 'ok',
        'service': 'employee-api',
        'version': '0.1.0',
        'database': 'ok',
      },
    );

    final response = await repository.fetchHealth();

    expect(response.status, 'ok');
    expect(response.service, 'employee-api');
    expect(response.version, '0.1.0');
    expect(response.database, 'ok');
  });

  test('converts a network exception into a user-safe failure', () async {
    when(
      () => apiClient.getMap(ApiEndpoints.health),
    ).thenThrow(const AppException.network('socket details'));

    expect(
      repository.fetchHealth,
      throwsA(
        isA<Failure>().having(
          (failure) => failure.message,
          'message',
          '无法连接后端服务，请检查服务是否启动。',
        ),
      ),
    );
  });
}
