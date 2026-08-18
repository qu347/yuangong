import 'dart:async';

import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/features/authentication/data/auth_repository.dart';
import 'package:employee_app/features/authentication/data/current_user.dart';
import 'package:employee_app/features/authentication/presentation/auth_session_store.dart';
import 'package:employee_app/features/authentication/presentation/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const loginTestUser = CurrentUser(
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

class LoginAuthRepository implements AuthRepository {
  final _authenticationLost = StreamController<void>.broadcast();
  Completer<CurrentUser>? pendingLogin;
  Object? loginError;

  @override
  Stream<void> get authenticationLost => _authenticationLost.stream;

  @override
  Future<CurrentUser> login({
    required String username,
    required String password,
  }) async {
    if (loginError case final error?) {
      throw error;
    }
    final pending = pendingLogin;
    if (pending != null) {
      return pending.future;
    }
    return loginTestUser;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<int> logoutAll() async => 0;

  @override
  Future<CurrentUser?> restoreSession() async => null;

  Future<void> close() => _authenticationLost.close();
}

class LoginHarness {
  LoginHarness(this.repository, this.store);

  final LoginAuthRepository repository;
  final AuthSessionStore store;

  Widget build() {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        authSessionStoreProvider.overrideWithValue(store),
      ],
      child: const MaterialApp(home: LoginPage()),
    );
  }
}

Future<void> enterCredentials(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('login_username')),
    'directory_demo',
  );
  await tester.enterText(
    find.byKey(const Key('login_password')),
    'test-only-password',
  );
}

void main() {
  testWidgets('validates required fields and hides the password', (
    tester,
  ) async {
    final repository = LoginAuthRepository();
    addTearDown(repository.close);
    final harness = LoginHarness(repository, AuthSessionStore());

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    final passwordField = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('login_password')),
        matching: find.byType(EditableText),
      ),
    );

    expect(passwordField.obscureText, isTrue);
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pump();
    expect(find.text('请输入用户名或工作邮箱'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
  });

  testWidgets('disables duplicate submission while login is pending', (
    tester,
  ) async {
    final repository = LoginAuthRepository()
      ..pendingLogin = Completer<CurrentUser>();
    addTearDown(repository.close);
    final harness = LoginHarness(repository, AuthSessionStore());

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await enterCredentials(tester);
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('login_submit')),
    );
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.pendingLogin!.complete(loginTestUser);
    await tester.pumpAndSettle();
  });

  testWidgets('keeps username and shows a safe error after failed login', (
    tester,
  ) async {
    final repository = LoginAuthRepository()
      ..loginError = const Failure.authentication('登录名或密码错误。');
    addTearDown(repository.close);
    final harness = LoginHarness(repository, AuthSessionStore());

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await enterCredentials(tester);
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    final usernameField = tester.widget<TextFormField>(
      find.byKey(const Key('login_username')),
    );
    expect(usernameField.controller!.text, 'directory_demo');
    expect(find.text('登录名或密码错误。'), findsOneWidget);
  });

  testWidgets('successful login publishes authenticated route state', (
    tester,
  ) async {
    final repository = LoginAuthRepository();
    final store = AuthSessionStore();
    addTearDown(repository.close);
    final harness = LoginHarness(repository, store);

    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await enterCredentials(tester);
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(store.status, AuthSessionStatus.authenticated);
  });
}
