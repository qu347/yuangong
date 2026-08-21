import 'dart:async';

import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/features/authentication/data/auth_repository.dart';
import 'package:employee_app/features/authentication/data/current_user.dart';
import 'package:employee_app/features/authentication/presentation/auth_controller.dart';
import 'package:employee_app/features/authentication/presentation/auth_session_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const testUser = CurrentUser(
  id: '00000000-0000-0000-0000-000000000101',
  username: 'directory_demo',
  displayName: '林知远',
  employeeId: '00000000-0000-0000-0000-000000000201',
  employeeNo: 'EMP-0001',
  department: CurrentUserDepartment(
    id: '00000000-0000-0000-0000-000000000301',
    code: 'ENG',
    name: '研发中心',
  ),
  roles: ['employee'],
);

class FakeAuthRepository implements AuthRepository {
  final authLossController = StreamController<void>.broadcast();
  CurrentUser? restoredUser;
  CurrentUser? loginUser = testUser;
  Object? loginError;
  int logoutCount = 0;

  @override
  Stream<void> get authenticationLost => authLossController.stream;

  @override
  Future<CurrentUser> login({
    required String username,
    required String password,
  }) async {
    if (loginError case final error?) {
      throw error;
    }
    return loginUser!;
  }

  @override
  Future<void> logout() async {
    logoutCount += 1;
  }

  @override
  Future<int> logoutAll() async => 0;

  @override
  Future<CurrentUser?> restoreSession() async => restoredUser;

  Future<void> close() => authLossController.close();
}

ProviderContainer createContainer(
  FakeAuthRepository repository,
  AuthSessionStore store,
) {
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      authSessionStoreProvider.overrideWithValue(store),
    ],
  );
}

void main() {
  test('session store owns and clears the authenticated employee id', () {
    final store = AuthSessionStore();

    store.markAuthenticated(testUser);
    expect(store.employeeId, testUser.employeeId);

    store.markLoading();
    expect(store.employeeId, isNull);

    store.markAuthenticated(testUser);
    store.markUnauthenticated();
    expect(store.employeeId, isNull);
  });

  test(
    'successful login publishes the user and authenticated route state',
    () async {
      final repository = FakeAuthRepository();
      final store = AuthSessionStore();
      final container = createContainer(repository, store);
      addTearDown(repository.close);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      final success = await container
          .read(authControllerProvider.notifier)
          .login(username: 'directory_demo', password: 'test-only-password');

      expect(success, isTrue);
      expect(container.read(authControllerProvider).value, testUser);
      expect(store.status, AuthSessionStatus.authenticated);
    },
  );

  test(
    'failed login keeps the route unauthenticated and exposes a safe failure',
    () async {
      final repository = FakeAuthRepository()
        ..loginError = const Failure(
          type: FailureType.authentication,
          message: '登录名或密码错误。',
        );
      final store = AuthSessionStore();
      final container = createContainer(repository, store);
      addTearDown(repository.close);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      final success = await container
          .read(authControllerProvider.notifier)
          .login(username: 'directory_demo', password: 'incorrect');

      expect(success, isFalse);
      expect(container.read(authControllerProvider).error, isA<Failure>());
      expect(store.status, AuthSessionStatus.unauthenticated);
    },
  );

  test(
    'logout clears repository state and publishes unauthenticated',
    () async {
      final repository = FakeAuthRepository()..restoredUser = testUser;
      final store = AuthSessionStore();
      final container = createContainer(repository, store);
      addTearDown(repository.close);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).logout();

      expect(repository.logoutCount, 1);
      expect(container.read(authControllerProvider).value, isNull);
      expect(store.status, AuthSessionStatus.unauthenticated);
    },
  );

  test('network authentication loss signs out the active session', () async {
    final repository = FakeAuthRepository()..restoredUser = testUser;
    final store = AuthSessionStore();
    final container = createContainer(repository, store);
    addTearDown(repository.close);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    repository.authLossController.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(repository.logoutCount, 1);
    expect(container.read(authControllerProvider).value, isNull);
    expect(store.status, AuthSessionStatus.unauthenticated);
  });
}
