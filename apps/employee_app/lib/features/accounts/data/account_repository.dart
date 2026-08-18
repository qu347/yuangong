import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'account.dart';

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => NetworkAccountRepository(ref.watch(apiClientProvider)),
);

abstract interface class AccountRepository {
  Future<AccountPage> fetchAccounts({
    String search,
    String? role,
    bool? isActive,
    int page,
  });
  Future<Account> fetchAccount(String id);
  Future<Account> updateEmail(String id, String email);
  Future<Account> setActive(String id, {required bool active});
  Future<Account> changeRole(String id, String role);
  Future<int> revokeSessions(String id);
  Future<AccountInvitation> createInvitation({
    required String employeeId,
    required String username,
    required String email,
    required String role,
  });
  Future<AccountInvitation> resendInvitation(String id);
  Future<bool> revokeInvitation(String id);
}

class NetworkAccountRepository implements AccountRepository {
  const NetworkAccountRepository(this._apiClient);
  final ApiClient _apiClient;

  @override
  Future<AccountPage> fetchAccounts({
    String search = '',
    String? role,
    bool? isActive,
    int page = 1,
  }) async {
    try {
      return AccountPage.fromJson(
        await _apiClient.getMap(
          ApiEndpoints.accounts,
          queryParameters: {
            if (search.trim().isNotEmpty) 'search': search.trim(),
            if (role != null && role.isNotEmpty) 'role': role,
            if (isActive != null) 'is_active': isActive.toString(),
            'page': page,
            'page_size': 20,
            'ordering': 'username',
          },
        ),
      );
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  @override
  Future<Account> fetchAccount(String id) =>
      _accountRequest(() => _apiClient.getMap('${ApiEndpoints.accounts}$id/'));

  @override
  Future<Account> updateEmail(String id, String email) => _accountRequest(
    () => _apiClient.patchMap(
      '${ApiEndpoints.accounts}$id/',
      data: {'email': email.trim()},
    ),
  );

  @override
  Future<Account> setActive(String id, {required bool active}) =>
      _actionAccount(
        '${ApiEndpoints.accounts}$id/${active ? 'activate' : 'deactivate'}/',
      );

  @override
  Future<Account> changeRole(String id, String role) async {
    try {
      return Account.fromJson(
        await _apiClient.postMap(
          '${ApiEndpoints.accounts}$id/change-role/',
          data: {'role': role},
        ),
      );
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  @override
  Future<int> revokeSessions(String id) async {
    try {
      final payload = await _apiClient.postMap(
        '${ApiEndpoints.accounts}$id/revoke-sessions/',
        data: const {},
      );
      final count = payload['revoked_sessions'];
      if (count is! int) throw const FormatException('invalid revoke count');
      return count;
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  @override
  Future<AccountInvitation> createInvitation({
    required String employeeId,
    required String username,
    required String email,
    required String role,
  }) => _invitationRequest(
    () => _apiClient.postMap(
      ApiEndpoints.invitations,
      data: {
        'employee_id': employeeId,
        'username': username.trim(),
        'email': email.trim(),
        'target_role': role,
      },
    ),
  );

  @override
  Future<AccountInvitation> resendInvitation(String id) => _invitationRequest(
    () => _apiClient.postMap(
      '${ApiEndpoints.invitations}$id/resend/',
      data: const {},
    ),
  );

  @override
  Future<bool> revokeInvitation(String id) async {
    try {
      final payload = await _apiClient.postMap(
        '${ApiEndpoints.invitations}$id/revoke/',
        data: const {},
      );
      final changed = payload['changed'];
      if (changed is! bool) {
        throw const FormatException('invalid invitation revoke');
      }
      return changed;
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  Future<Account> _actionAccount(String path) async {
    try {
      final payload = await _apiClient.postMap(path, data: const {});
      final account = payload['account'];
      if (account is! Map<String, dynamic>) {
        throw const FormatException('invalid account action');
      }
      return Account.fromJson(account);
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  Future<Account> _accountRequest(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    try {
      return Account.fromJson(await request());
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  Future<AccountInvitation> _invitationRequest(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    try {
      return AccountInvitation.fromJson(await request());
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  Failure _failureFor(AppException error) => switch (error.type) {
    AppExceptionType.network => const Failure.network(),
    AppExceptionType.unauthorized => const Failure.authentication(),
    AppExceptionType.forbidden => const Failure.permission(),
    AppExceptionType.validation => const Failure.validation(),
    AppExceptionType.conflict => const Failure.conflict(),
    AppExceptionType.protocol => const Failure.service(),
    AppExceptionType.unexpected => const Failure(
      type: FailureType.unexpected,
      message: '账号管理操作失败，请稍后重试。',
    ),
  };
}
