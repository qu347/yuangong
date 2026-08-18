import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_controller.dart';
import '../data/account_security_repository.dart';
import '../data/account_session.dart';

final accountSecurityControllerProvider = Provider<AccountSecurityController>(
  AccountSecurityController.new,
);

final accountSessionListProvider =
    FutureProvider.autoDispose<List<AccountSession>>(
      (ref) => ref.watch(accountSecurityRepositoryProvider).fetchSessions(),
      retry: (retryCount, error) => null,
    );

class AccountSecurityController {
  AccountSecurityController(this._ref);
  final Ref _ref;

  AccountSecurityRepository get _repository =>
      _ref.read(accountSecurityRepositoryProvider);

  Future<void> acceptInvitation(String token, String password) =>
      _repository.acceptInvitation(token: token, newPassword: password);

  Future<String> requestReset(String identifier) =>
      _repository.requestPasswordReset(identifier);

  Future<void> confirmReset(String token, String password) =>
      _repository.confirmPasswordReset(token: token, newPassword: password);

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    await _repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    await _ref.read(authControllerProvider.notifier).logout();
  }

  Future<bool> revokeSession(AccountSession session) async {
    final changed = await _repository.revokeSession(session.id);
    if (session.isCurrent) {
      await _ref.read(authControllerProvider.notifier).logout();
    } else {
      _ref.invalidate(accountSessionListProvider);
    }
    return changed;
  }

  Future<int> revokeOthers() async {
    final count = await _repository.revokeOtherSessions();
    _ref.invalidate(accountSessionListProvider);
    return count;
  }
}
