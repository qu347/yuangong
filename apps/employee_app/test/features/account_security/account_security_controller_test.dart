import 'dart:async';

import 'package:employee_app/features/account_security/data/account_security_repository.dart';
import 'package:employee_app/features/account_security/data/account_session.dart';
import 'package:employee_app/features/account_security/presentation/account_security_controller.dart';
import 'package:employee_app/features/authentication/data/auth_repository.dart';
import 'package:employee_app/features/authentication/data/current_user.dart';
import 'package:employee_app/features/authentication/presentation/auth_controller.dart';
import 'package:employee_app/features/authentication/presentation/auth_session_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const currentUser = CurrentUser(
  id: 'user-id',
  username: 'security.user',
  displayName: '安全测试用户',
  employeeId: null,
  employeeNo: null,
  department: null,
  roles: ['employee'],
);

class ControllerAuthRepository implements AuthRepository {
  final loss = StreamController<void>.broadcast();
  var logoutCount = 0;

  @override
  Stream<void> get authenticationLost => loss.stream;

  @override
  Future<CurrentUser> login({
    required String username,
    required String password,
  }) async => currentUser;

  @override
  Future<void> logout() async => logoutCount += 1;

  @override
  Future<int> logoutAll() async => 0;

  @override
  Future<CurrentUser?> restoreSession() async => currentUser;

  Future<void> close() => loss.close();
}

class ControllerSecurityRepository implements AccountSecurityRepository {
  var changedPasswords = 0;
  var revokedSessions = 0;

  @override
  Future<void> acceptInvitation({
    required String token,
    required String newPassword,
  }) async {}

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async => changedPasswords += 1;

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {}

  @override
  Future<List<AccountSession>> fetchSessions() async => [];

  @override
  Future<String> requestPasswordReset(String identifier) async => 'accepted';

  @override
  Future<int> revokeOtherSessions() async => 0;

  @override
  Future<bool> revokeSession(String id) async {
    revokedSessions += 1;
    return true;
  }
}

ProviderContainer createContainer(
  ControllerAuthRepository auth,
  ControllerSecurityRepository security,
  AuthSessionStore store,
) => ProviderContainer(
  overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    accountSecurityRepositoryProvider.overrideWithValue(security),
    authSessionStoreProvider.overrideWithValue(store),
  ],
);

void main() {
  test(
    'password change clears the authenticated application session',
    () async {
      final auth = ControllerAuthRepository();
      final security = ControllerSecurityRepository();
      final store = AuthSessionStore();
      final container = createContainer(auth, security, store);
      addTearDown(auth.close);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      await container
          .read(accountSecurityControllerProvider)
          .changePassword('current-password', 'Quartz!Forest7Harbor');

      expect(security.changedPasswords, 1);
      expect(auth.logoutCount, 1);
      expect(store.status, AuthSessionStatus.unauthenticated);
    },
  );

  test('revoking the current session signs out locally', () async {
    final auth = ControllerAuthRepository();
    final security = ControllerSecurityRepository();
    final store = AuthSessionStore();
    final container = createContainer(auth, security, store);
    addTearDown(auth.close);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    final session = AccountSession(
      id: 'session-id',
      clientPlatform: 'windows',
      clientName: 'Windows 客户端',
      appVersion: '0.1.0',
      createdAt: DateTime.utc(2026, 8, 18),
      lastSeenAt: DateTime.utc(2026, 8, 18),
      expiresAt: DateTime.utc(2026, 8, 25),
      isCurrent: true,
    );

    await container
        .read(accountSecurityControllerProvider)
        .revokeSession(session);

    expect(security.revokedSessions, 1);
    expect(auth.logoutCount, 1);
    expect(store.status, AuthSessionStatus.unauthenticated);
  });
}
