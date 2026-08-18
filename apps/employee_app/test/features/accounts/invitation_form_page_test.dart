import 'package:employee_app/features/accounts/data/account.dart';
import 'package:employee_app/features/accounts/data/account_repository.dart';
import 'package:employee_app/features/accounts/presentation/invitation_form_page.dart';
import 'package:employee_app/features/employees/data/employee.dart';
import 'package:employee_app/features/employees/data/employee_page.dart';
import 'package:employee_app/features/employees/data/employee_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class InvitationEmployeeRepository extends EmployeeRepository {
  @override
  Future<Employee> fetchEmployee(String id) => throw UnimplementedError();

  @override
  Future<EmployeePage> fetchEmployees({
    String search = '',
    String? departmentId,
    String? status,
    int page = 1,
    int pageSize = 20,
    String ordering = 'employee_no',
  }) async =>
      const EmployeePage(count: 0, next: null, previous: null, results: []);
}

class InvitationAccountRepository implements AccountRepository {
  @override
  Future<Account> changeRole(String id, String role) =>
      throw UnimplementedError();

  @override
  Future<AccountInvitation> createInvitation({
    required String employeeId,
    required String username,
    required String email,
    required String role,
  }) => throw UnimplementedError();

  @override
  Future<Account> fetchAccount(String id) => throw UnimplementedError();

  @override
  Future<AccountPage> fetchAccounts({
    String search = '',
    String? role,
    bool? isActive,
    int page = 1,
  }) => throw UnimplementedError();

  @override
  Future<List<AccountInvitation>> fetchInvitations() =>
      throw UnimplementedError();

  @override
  Future<AccountInvitation> resendInvitation(String id) =>
      throw UnimplementedError();

  @override
  Future<bool> revokeInvitation(String id) => throw UnimplementedError();

  @override
  Future<int> revokeSessions(String id) => throw UnimplementedError();

  @override
  Future<Account> setActive(String id, {required bool active}) =>
      throw UnimplementedError();

  @override
  Future<Account> updateEmail(String id, String email) =>
      throw UnimplementedError();
}

void main() {
  testWidgets('dirty invitation form asks before discarding changes', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('返回目标')),
        ),
        GoRoute(path: '/form', builder: (_, _) => const InvitationFormPage()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          employeeRepositoryProvider.overrideWithValue(
            InvitationEmployeeRepository(),
          ),
          accountRepositoryProvider.overrideWithValue(
            InvitationAccountRepository(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/form');
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '登录名'),
      'unsaved.invitation',
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('放弃未保存更改？'), findsOneWidget);
    expect(find.text('继续编辑'), findsOneWidget);
    expect(find.text('放弃更改'), findsOneWidget);
  });
}
