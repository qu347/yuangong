import 'package:employee_app/core/platform/secure_storage_service.dart';
import 'package:employee_app/core/storage/token_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSecureStorageService implements SecureStorageService {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  late FakeSecureStorageService secureStorage;
  late SecureTokenStorage tokenStorage;

  setUp(() {
    secureStorage = FakeSecureStorageService();
    tokenStorage = SecureTokenStorage(secureStorage);
  });

  test(
    'stores access and refresh tokens under separate private keys',
    () async {
      await tokenStorage.saveTokens(
        accessToken: 'access-test-value',
        refreshToken: 'refresh-test-value',
      );

      expect(await tokenStorage.readAccessToken(), 'access-test-value');
      expect(await tokenStorage.readRefreshToken(), 'refresh-test-value');
      expect(secureStorage.values.length, 2);
    },
  );

  test('updates only the access token after a refresh', () async {
    await tokenStorage.saveTokens(
      accessToken: 'old-access',
      refreshToken: 'stable-refresh',
    );

    await tokenStorage.saveAccessToken('new-access');

    expect(await tokenStorage.readAccessToken(), 'new-access');
    expect(await tokenStorage.readRefreshToken(), 'stable-refresh');
  });

  test('clears both tokens during logout', () async {
    await tokenStorage.saveTokens(
      accessToken: 'access-test-value',
      refreshToken: 'refresh-test-value',
    );

    await tokenStorage.clear();

    expect(await tokenStorage.readAccessToken(), isNull);
    expect(await tokenStorage.readRefreshToken(), isNull);
  });
}
