import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/storage/token_storage.dart';
import 'auth_tokens.dart';
import 'current_user.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => NetworkAuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
  ),
);

abstract interface class AuthRepository {
  Stream<void> get authenticationLost;

  Future<CurrentUser> login({
    required String username,
    required String password,
  });

  Future<CurrentUser?> restoreSession();
  Future<void> logout();
  Future<int> logoutAll();
}

class NetworkAuthRepository implements AuthRepository {
  NetworkAuthRepository(this._apiClient, this._tokenStorage);

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  @override
  Stream<void> get authenticationLost => _apiClient.authenticationLost;

  @override
  Future<CurrentUser> login({
    required String username,
    required String password,
  }) async {
    try {
      final tokenPayload = await _apiClient.postMap(
        ApiEndpoints.login,
        data: {'username': username, 'password': password},
        authenticated: false,
      );
      final tokens = AuthTokens.fromJson(tokenPayload);
      await _tokenStorage.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return await _fetchCurrentUser();
    } on AppException catch (error) {
      await _tokenStorage.clear();
      throw _failureFor(error, duringLogin: true);
    } on FormatException {
      await _tokenStorage.clear();
      throw const Failure.data();
    }
  }

  @override
  Future<CurrentUser?> restoreSession() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }
    try {
      return await _fetchCurrentUser();
    } on AppException catch (error) {
      if (error.type == AppExceptionType.unauthorized) {
        await _tokenStorage.clear();
      }
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  Future<CurrentUser> _fetchCurrentUser() async {
    return CurrentUser.fromJson(await _apiClient.getMap(ApiEndpoints.me));
  }

  Failure _failureFor(AppException error, {bool duringLogin = false}) {
    return switch (error.type) {
      AppExceptionType.network => const Failure.network(),
      AppExceptionType.unauthorized when duringLogin =>
        const Failure.authentication('登录名或密码错误。'),
      AppExceptionType.unauthorized => const Failure.authentication(),
      AppExceptionType.forbidden => const Failure.permission(),
      AppExceptionType.validation => const Failure.validation(),
      AppExceptionType.conflict => const Failure.conflict(),
      AppExceptionType.protocol => const Failure.service(),
      AppExceptionType.unexpected => const Failure(
        type: FailureType.unexpected,
        message: '发生未知错误，请稍后重试。',
      ),
    };
  }

  @override
  Future<void> logout() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _apiClient.postVoid(
          ApiEndpoints.logout,
          data: {'refresh': refreshToken},
        );
      }
    } on Object {
      // Local logout must complete even if the server cannot revoke the refresh token.
    } finally {
      await _tokenStorage.clear();
    }
  }

  @override
  Future<int> logoutAll() async {
    try {
      final payload = await _apiClient.postMap(
        ApiEndpoints.logoutAll,
        data: const {},
      );
      final revokedSessions = payload['revoked_sessions'];
      if (revokedSessions is! int || revokedSessions < 0) {
        throw const FormatException('invalid revoked session count');
      }
      return revokedSessions;
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }
}
