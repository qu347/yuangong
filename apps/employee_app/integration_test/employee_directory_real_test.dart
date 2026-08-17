import 'package:employee_app/app/app.dart';
import 'package:employee_app/core/platform/secure_storage_service.dart';
import 'package:employee_app/core/storage/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const runRealDirectoryTests = bool.fromEnvironment('RUN_REAL_DIRECTORY_TESTS');
const demoUsername = String.fromEnvironment('DEMO_USERNAME');
const demoPassword = String.fromEnvironment('DEMO_PASSWORD');

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(finder, findsWidgets);
}

Future<void> pumpUntilLoginEnabled(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final finder = find.byKey(const Key('login_submit'));
  final deadline = DateTime.now().add(timeout);
  var enabled = false;
  while (!enabled && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    final buttons = tester.widgetList<FilledButton>(finder);
    enabled = buttons.isNotEmpty && buttons.single.onPressed != null;
  }
  expect(enabled, isTrue);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'completes login directory detail department and logout against the real API',
    (tester) async {
      expect(demoUsername, isNotEmpty);
      expect(demoPassword, isNotEmpty);
      final tokenStorage = SecureTokenStorage(FlutterSecureStorageService());
      await tokenStorage.clear();
      addTearDown(tokenStorage.clear);

      await tester.pumpWidget(const ProviderScope(child: EmployeeApp()));
      await pumpUntilFound(tester, find.text('登录员工目录'));
      await pumpUntilLoginEnabled(tester);
      await tester.enterText(
        find.byKey(const Key('login_username')),
        demoUsername,
      );
      await tester.enterText(
        find.byKey(const Key('login_password')),
        demoPassword,
      );
      await tester.tap(find.byKey(const Key('login_submit')));

      await pumpUntilFound(tester, find.text('员工目录'));
      await pumpUntilFound(tester, find.text('林知远'));
      await tester.enterText(
        find.byKey(const Key('employee_search')),
        'EMP-0001',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await pumpUntilFound(tester, find.text('EMP-0001'));
      await tester.tap(find.text('林知远').first);

      await pumpUntilFound(tester, find.text('员工详情'));
      await pumpUntilFound(tester, find.text('lin.zhiyuan@example.test'));
      expect(find.text('研发中心'), findsWidgets);
      await tester.tap(find.byTooltip('返回员工目录'));
      await pumpUntilFound(tester, find.text('员工目录'));

      await tester.tap(find.byIcon(Icons.account_tree_outlined));
      await pumpUntilFound(tester, find.text('部门目录'));
      await pumpUntilFound(tester, find.text('企业总部'));

      await tester.tap(find.byKey(const Key('shell_logout')));
      await pumpUntilFound(tester, find.text('登录员工目录'));
    },
    skip: !runRealDirectoryTests,
  );
}
