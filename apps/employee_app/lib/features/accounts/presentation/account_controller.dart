import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account.dart';
import '../data/account_repository.dart';

final accountListProvider = FutureProvider.autoDispose<AccountPage>(
  (ref) => ref.watch(accountRepositoryProvider).fetchAccounts(),
  retry: (retryCount, error) => null,
);

final accountDetailProvider = FutureProvider.autoDispose
    .family<Account, String>(
      (ref, id) => ref.watch(accountRepositoryProvider).fetchAccount(id),
      retry: (retryCount, error) => null,
    );

final accountControllerProvider = Provider<AccountController>(
  AccountController.new,
);

class AccountController {
  AccountController(this._ref);
  final Ref _ref;
  AccountRepository get repository => _ref.read(accountRepositoryProvider);

  void refresh([String? id]) {
    _ref.invalidate(accountListProvider);
    if (id != null) _ref.invalidate(accountDetailProvider(id));
  }

  Future<Account> updateEmail(String id, String email) async {
    final result = await repository.updateEmail(id, email);
    refresh(id);
    return result;
  }

  Future<Account> setActive(String id, bool active) async {
    final result = await repository.setActive(id, active: active);
    refresh(id);
    return result;
  }

  Future<Account> changeRole(String id, String role) async {
    final result = await repository.changeRole(id, role);
    refresh(id);
    return result;
  }

  Future<int> revokeSessions(String id) async {
    final result = await repository.revokeSessions(id);
    refresh(id);
    return result;
  }
}
