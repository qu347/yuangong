import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/current_user.dart';
import 'auth_session_store.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, CurrentUser?>(AuthController.new);

class AuthController extends AsyncNotifier<CurrentUser?> {
  late AuthRepository _repository;
  late AuthSessionStore _sessionStore;

  @override
  Future<CurrentUser?> build() async {
    _repository = ref.watch(authRepositoryProvider);
    _sessionStore = ref.watch(authSessionStoreProvider);
    final subscription = _repository.authenticationLost.listen((_) {
      unawaited(_handleAuthenticationLost());
    });
    ref.onDispose(() {
      unawaited(subscription.cancel());
    });

    try {
      final user = await _repository.restoreSession();
      if (user == null) {
        _sessionStore.markUnauthenticated();
      } else {
        _sessionStore.markAuthenticated(user);
      }
      return user;
    } on Object {
      _sessionStore.markUnauthenticated();
      return null;
    }
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    state = const AsyncLoading();
    try {
      final user = await _repository.login(
        username: username,
        password: password,
      );
      state = AsyncData(user);
      _sessionStore.markAuthenticated(user);
      return true;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      _sessionStore.markUnauthenticated();
      return false;
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    state = const AsyncData(null);
    _sessionStore.markUnauthenticated();
  }

  Future<int> logoutAll() async {
    final revokedSessions = await _repository.logoutAll();
    await logout();
    return revokedSessions;
  }

  Future<void> _handleAuthenticationLost() => logout();
}
