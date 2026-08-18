import 'package:employee_app/app/app.dart';
import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/core/network/api_endpoints.dart';
import 'package:employee_app/core/platform/secure_storage_service.dart';
import 'package:employee_app/core/storage/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const runRealAccountSecurityTests = bool.fromEnvironment(
  'RUN_REAL_ACCOUNT_SECURITY_TESTS',
);
const invitationCode = String.fromEnvironment('ACCOUNT_INVITATION_CODE');
const invitedIdentifier = String.fromEnvironment('ACCOUNT_IDENTIFIER');
const initialPassword = String.fromEnvironment('ACCOUNT_INITIAL_PASSWORD');
const changedPassword = String.fromEnvironment('ACCOUNT_CHANGED_PASSWORD');
const systemAdminIdentifier = String.fromEnvironment('SYSTEM_ADMIN_IDENTIFIER');
const systemAdminPassword = String.fromEnvironment('SYSTEM_ADMIN_PASSWORD');

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(finder, findsWidgets);
}

Future<void> login(
  WidgetTester tester,
  String identifier,
  String password,
) async {
  await pumpUntilFound(tester, find.byKey(const Key('login_username')));
  await tester.enterText(find.byKey(const Key('login_username')), identifier);
  await tester.enterText(find.byKey(const Key('login_password')), password);
  await tester.tap(find.byKey(const Key('login_submit')));
  await pumpUntilFound(tester, find.text('员工目录'));
}

Future<void> openSecurity(WidgetTester tester) async {
  final destination = find.byIcon(Icons.security_outlined).hitTestable();
  await pumpUntilFound(tester, destination);
  await tester.tap(destination);
  await pumpUntilFound(tester, find.text('安全设置'));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('completes shared account security flow against the real API', (
    tester,
  ) async {
    for (final value in [
      invitationCode,
      invitedIdentifier,
      initialPassword,
      changedPassword,
      systemAdminIdentifier,
      systemAdminPassword,
    ]) {
      expect(value, isNotEmpty);
    }
    final tokenStorage = SecureTokenStorage(FlutterSecureStorageService());
    await tokenStorage.clear();
    addTearDown(tokenStorage.clear);

    await tester.pumpWidget(const ProviderScope(child: EmployeeApp()));
    await pumpUntilFound(tester, find.text('接受账号邀请'));
    await tester.tap(find.text('接受账号邀请'));
    await pumpUntilFound(tester, find.byKey(const Key('invitation_token')));
    await tester.enterText(
      find.byKey(const Key('invitation_token')),
      invitationCode,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '新密码'),
      initialPassword,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '确认新密码'),
      initialPassword,
    );
    await tester.tap(find.byKey(const Key('invitation_accept_submit')));
    await pumpUntilFound(tester, find.text('登录员工目录'));

    await login(tester, invitedIdentifier, initialPassword);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EmployeeApp)),
    );
    await container
        .read(apiClientProvider)
        .postMap(
          ApiEndpoints.login,
          data: {
            'identifier': invitedIdentifier,
            'password': initialPassword,
            'client_platform': 'unknown',
            'client_name': 'Secondary integration session',
            'app_version': '0.1.0-test',
          },
          authenticated: false,
        );

    await openSecurity(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, '当前密码'),
      initialPassword,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '新密码'),
      changedPassword,
    );
    await tester.tap(find.text('修改密码并重新登录'));
    await pumpUntilFound(tester, find.text('登录员工目录'));
    await login(tester, invitedIdentifier, changedPassword);

    await openSecurity(tester);
    await tester.tap(find.text('管理登录设备'));
    await pumpUntilFound(tester, find.text('登录会话'));
    await pumpUntilFound(tester, find.text('当前设备'));
    await tester.tap(find.text('撤销其他会话'));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byKey(const Key('shell_logout')));
    await pumpUntilFound(tester, find.text('登录员工目录'));
    await login(tester, systemAdminIdentifier, systemAdminPassword);
    await openSecurity(tester);
    await tester.tap(find.byKey(const Key('account_admin_entry')));
    await pumpUntilFound(tester, find.text('账号管理'));
    await pumpUntilFound(tester, find.text(invitedIdentifier));
    await tester.tap(find.text(invitedIdentifier).first);
    await pumpUntilFound(tester, find.byKey(const Key('account_deactivate')));

    await tester.tap(find.byKey(const Key('account_deactivate')));
    await pumpUntilFound(tester, find.text('确认停用账号？'));
    await tester.tap(find.text('确认停用'));
    await pumpUntilFound(tester, find.byKey(const Key('account_activate')));
    await tester.tap(find.byKey(const Key('account_activate')));
    await pumpUntilFound(tester, find.text('确认恢复账号？'));
    await tester.tap(find.text('确认恢复'));
    await pumpUntilFound(tester, find.byKey(const Key('account_deactivate')));

    await tester.tap(find.byKey(const Key('shell_logout')));
    await pumpUntilFound(tester, find.text('登录员工目录'));
  }, skip: !runRealAccountSecurityTests);
}
