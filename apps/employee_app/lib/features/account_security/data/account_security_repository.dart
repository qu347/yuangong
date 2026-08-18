import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'account_session.dart';

final accountSecurityRepositoryProvider = Provider<AccountSecurityRepository>(
  (ref) => NetworkAccountSecurityRepository(ref.watch(apiClientProvider)),
);

abstract interface class AccountSecurityRepository {
  Future<void> acceptInvitation({
    required String token,
    required String newPassword,
  });
  Future<String> requestPasswordReset(String identifier);
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  });
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
  Future<List<AccountSession>> fetchSessions();
  Future<bool> revokeSession(String id);
  Future<int> revokeOtherSessions();
}

class NetworkAccountSecurityRepository implements AccountSecurityRepository {
  const NetworkAccountSecurityRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<void> acceptInvitation({
    required String token,
    required String newPassword,
  }) => _voidRequest(
    () => _apiClient.postVoid(
      ApiEndpoints.invitationAccept,
      data: {'token': token.trim(), 'new_password': newPassword},
      authenticated: false,
    ),
  );

  @override
  Future<String> requestPasswordReset(String identifier) async {
    try {
      final payload = await _apiClient.postMap(
        ApiEndpoints.passwordResetRequest,
        data: {'identifier': identifier.trim()},
        authenticated: false,
      );
      final message = payload['message'];
      if (message is! String || message.isEmpty) {
        throw const FormatException('invalid reset response');
      }
      return message;
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) => _voidRequest(
    () => _apiClient.postVoid(
      ApiEndpoints.passwordResetConfirm,
      data: {'token': token.trim(), 'new_password': newPassword},
      authenticated: false,
    ),
  );

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _voidRequest(
    () => _apiClient.postVoid(
      ApiEndpoints.passwordChange,
      data: {'current_password': currentPassword, 'new_password': newPassword},
    ),
  );

  @override
  Future<List<AccountSession>> fetchSessions() async {
    try {
      return List<AccountSession>.unmodifiable(
        (await _apiClient.getList(ApiEndpoints.sessions)).map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('invalid session item');
          }
          return AccountSession.fromJson(item);
        }),
      );
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  @override
  Future<bool> revokeSession(String id) async {
    try {
      final payload = await _apiClient.postMap(
        '${ApiEndpoints.sessions}$id/revoke/',
        data: const {},
      );
      final changed = payload['changed'];
      if (changed is! bool) {
        throw const FormatException('invalid revoke response');
      }
      return changed;
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  @override
  Future<int> revokeOtherSessions() async {
    try {
      final payload = await _apiClient.postMap(
        ApiEndpoints.revokeOtherSessions,
        data: const {},
      );
      final count = payload['revoked_sessions'];
      if (count is! int || count < 0) {
        throw const FormatException('invalid revoke count');
      }
      return count;
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  Future<void> _voidRequest(Future<void> Function() request) async {
    try {
      await request();
    } on AppException catch (error) {
      throw _failureFor(error);
    }
  }

  Failure _failureFor(AppException error) => switch (error.type) {
    AppExceptionType.network => const Failure.network(),
    AppExceptionType.unauthorized => const Failure.authentication(),
    AppExceptionType.forbidden => const Failure.permission(),
    AppExceptionType.validation => const Failure.validation(
      '一次性代码无效或密码不符合安全要求。',
    ),
    AppExceptionType.conflict => const Failure.conflict(),
    AppExceptionType.protocol => const Failure.service(),
    AppExceptionType.unexpected => const Failure(
      type: FailureType.unexpected,
      message: '账号安全操作失败，请稍后重试。',
    ),
  };
}
