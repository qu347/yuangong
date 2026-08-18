import 'package:employee_app/core/errors/app_exception.dart';
import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/core/network/api_endpoints.dart';
import 'package:employee_app/core/storage/token_storage.dart';
import 'package:employee_app/features/authentication/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

class MemoryTokenStorage implements TokenStorage {
  String? accessToken;
  String? refreshToken;
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount += 1;
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> saveAccessToken(String accessToken) async {
    this.accessToken = accessToken;
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }
}

const currentUserPayload = <String, dynamic>{
  'id': '00000000-0000-0000-0000-000000000101',
  'username': 'directory_demo',
  'display_name': '林知远',
  'employee_id': '00000000-0000-0000-0000-000000000201',
  'employee_no': 'EMP-0001',
  'department': {
    'id': '00000000-0000-0000-0000-000000000301',
    'code': 'ENG',
    'name': '研发中心',
  },
  'roles': ['employee'],
  'capabilities': {
    'can_manage_employees': true,
    'can_manage_departments': true,
    'can_manage_positions': false,
    'can_view_audit': true,
    'can_logout_all': true,
  },
};

void main() {
  late MockApiClient apiClient;
  late MemoryTokenStorage tokenStorage;
  late NetworkAuthRepository repository;

  setUp(() {
    apiClient = MockApiClient();
    tokenStorage = MemoryTokenStorage();
    repository = NetworkAuthRepository(apiClient, tokenStorage);
  });

  test('login stores both tokens and returns the current user', () async {
    when(
      () => apiClient.postMap(
        ApiEndpoints.login,
        data: any(named: 'data'),
        authenticated: false,
      ),
    ).thenAnswer(
      (_) async => {
        'access': 'access-test-value',
        'refresh': 'refresh-test-value',
      },
    );
    when(
      () => apiClient.getMap(ApiEndpoints.me),
    ).thenAnswer((_) async => currentUserPayload);

    final user = await repository.login(
      username: 'directory_demo',
      password: 'test-only-password',
    );

    expect(user.employeeNo, 'EMP-0001');
    expect(user.department?.name, '研发中心');
    expect(user.capabilities.canManageEmployees, isTrue);
    expect(user.capabilities.canManagePositions, isFalse);
    expect(tokenStorage.accessToken, 'access-test-value');
    expect(tokenStorage.refreshToken, 'refresh-test-value');
  });

  test(
    'invalid credentials become a user-safe authentication failure',
    () async {
      when(
        () => apiClient.postMap(
          ApiEndpoints.login,
          data: any(named: 'data'),
          authenticated: false,
        ),
      ).thenThrow(const AppException.unauthorized('private server detail'));

      await expectLater(
        repository.login(username: 'directory_demo', password: 'incorrect'),
        throwsA(
          isA<Failure>().having(
            (failure) => failure.message,
            'message',
            '登录名或密码错误。',
          ),
        ),
      );
    },
  );

  test(
    'restore returns null without a refresh token and avoids the API',
    () async {
      final user = await repository.restoreSession();

      expect(user, isNull);
      verifyNever(() => apiClient.getMap(any()));
    },
  );

  test(
    'logout calls the server before clearing both persisted tokens',
    () async {
      tokenStorage
        ..accessToken = 'access-test-value'
        ..refreshToken = 'refresh-test-value';
      when(
        () => apiClient.postVoid(
          ApiEndpoints.logout,
          data: {'refresh': 'refresh-test-value'},
        ),
      ).thenAnswer((_) async {});

      await repository.logout();

      verify(
        () => apiClient.postVoid(
          ApiEndpoints.logout,
          data: {'refresh': 'refresh-test-value'},
        ),
      ).called(1);
      expect(tokenStorage.clearCount, 1);
      expect(tokenStorage.accessToken, isNull);
      expect(tokenStorage.refreshToken, isNull);
    },
  );

  test(
    'logout still clears local tokens when the server is unavailable',
    () async {
      tokenStorage
        ..accessToken = 'access-test-value'
        ..refreshToken = 'refresh-test-value';
      when(
        () => apiClient.postVoid(
          ApiEndpoints.logout,
          data: {'refresh': 'refresh-test-value'},
        ),
      ).thenThrow(const AppException.network('private network detail'));

      await repository.logout();

      expect(tokenStorage.clearCount, 1);
      expect(tokenStorage.accessToken, isNull);
      expect(tokenStorage.refreshToken, isNull);
    },
  );

  test('logout all returns the revoked session count', () async {
    when(
      () => apiClient.postMap(ApiEndpoints.logoutAll, data: const {}),
    ).thenAnswer((_) async => {'revoked_sessions': 3});

    final revokedSessions = await repository.logoutAll();

    expect(revokedSessions, 3);
  });
}
