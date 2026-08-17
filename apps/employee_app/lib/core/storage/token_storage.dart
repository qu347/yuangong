import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/secure_storage_service.dart';

final secureStorageServiceProvider = Provider<SecureStorageService>(
  (ref) => FlutterSecureStorageService(),
);

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => SecureTokenStorage(ref.watch(secureStorageServiceProvider)),
);

abstract interface class TokenStorage {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });
  Future<void> saveAccessToken(String accessToken);
  Future<void> clear();
}

class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage(this._storage);

  static const _accessTokenKey = 'employee_app_access_token';
  static const _refreshTokenKey = 'employee_app_refresh_token';

  final SecureStorageService _storage;

  @override
  Future<String?> readAccessToken() => _storage.read(_accessTokenKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(_refreshTokenKey);

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(_accessTokenKey, accessToken);
    await _storage.write(_refreshTokenKey, refreshToken);
  }

  @override
  Future<void> saveAccessToken(String accessToken) =>
      _storage.write(_accessTokenKey, accessToken);

  @override
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(_accessTokenKey),
      _storage.delete(_refreshTokenKey),
    ]);
  }
}
