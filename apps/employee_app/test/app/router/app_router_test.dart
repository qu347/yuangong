import 'dart:async';

import 'package:employee_app/app/router/app_router.dart';
import 'package:employee_app/features/authentication/data/auth_repository.dart';
import 'package:employee_app/features/authentication/data/current_user.dart';
import 'package:employee_app/features/authentication/presentation/auth_session_store.dart';
import 'package:employee_app/features/departments/data/department.dart';
import 'package:employee_app/features/departments/data/department_repository.dart';
import 'package:employee_app/features/employees/data/employee.dart';
import 'package:employee_app/features/employees/data/employee_page.dart';
import 'package:employee_app/features/employees/data/employee_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class RouterAuthRepository implements AuthRepository {
  final _authenticationLost = StreamController<void>.broadcast();

  @override
  Stream<void> get authenticationLost => _authenticationLost.stream;

  @override
  Future<CurrentUser> login({
    required String username,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<int> logoutAll() async => 0;

  @override
  Future<CurrentUser?> restoreSession() async => null;

  Future<void> close() => _authenticationLost.close();
}

class RouterEmployeeRepository extends EmployeeRepository {
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

class RouterDepartmentRepository extends DepartmentRepository {
  @override
  Future<List<Department>> fetchDepartments() async => const [];
}

Widget routerApp({
  required AuthSessionStore store,
  required RouterAuthRepository repository,
  required String initialLocation,
}) {
  return ProviderScope(
    overrides: [
      authSessionStoreProvider.overrideWithValue(store),
      authRepositoryProvider.overrideWithValue(repository),
      employeeRepositoryProvider.overrideWithValue(RouterEmployeeRepository()),
      departmentRepositoryProvider.overrideWithValue(
        RouterDepartmentRepository(),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: createAppRouter(store, initialLocation: initialLocation),
    ),
  );
}

void main() {
  testWidgets('keeps public recovery routes available without authentication', (
    tester,
  ) async {
    final store = AuthSessionStore()..markUnauthenticated();
    final repository = RouterAuthRepository();
    addTearDown(repository.close);

    await tester.pumpWidget(
      routerApp(
        store: store,
        repository: repository,
        initialLocation: '/forgot-password',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('忘记密码'), findsOneWidget);
    expect(find.text('登录员工目录'), findsNothing);
  });

  testWidgets('redirects an unauthenticated business route to login', (
    tester,
  ) async {
    final store = AuthSessionStore()..markUnauthenticated();
    final repository = RouterAuthRepository();
    addTearDown(repository.close);

    await tester.pumpWidget(
      routerApp(
        store: store,
        repository: repository,
        initialLocation: '/employees',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录员工目录'), findsOneWidget);
    expect(find.text('通讯录'), findsNothing);
  });

  testWidgets('redirects an authenticated login route to employees', (
    tester,
  ) async {
    final store = AuthSessionStore()..markAuthenticated();
    final repository = RouterAuthRepository();
    addTearDown(repository.close);

    await tester.pumpWidget(
      routerApp(
        store: store,
        repository: repository,
        initialLocation: '/login',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('通讯录'), findsWidgets);
    expect(find.text('登录员工目录'), findsNothing);
  });

  testWidgets('keeps loading and direct detail routes behind login', (
    tester,
  ) async {
    final store = AuthSessionStore();
    final repository = RouterAuthRepository();
    addTearDown(repository.close);

    await tester.pumpWidget(
      routerApp(
        store: store,
        repository: repository,
        initialLocation: '/employees/00000000-0000-0000-0000-000000000201',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录员工目录'), findsOneWidget);
  });

  testWidgets('auth loss redirects an active directory session once', (
    tester,
  ) async {
    final store = AuthSessionStore()..markAuthenticated();
    final repository = RouterAuthRepository();
    addTearDown(repository.close);

    await tester.pumpWidget(
      routerApp(
        store: store,
        repository: repository,
        initialLocation: '/employees',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('通讯录'), findsWidgets);

    store.markUnauthenticated();
    await tester.pumpAndSettle();

    expect(find.text('登录员工目录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('redirects a management deep link when capability is absent', (
    tester,
  ) async {
    final store = AuthSessionStore()..markAuthenticated();
    final repository = RouterAuthRepository();
    addTearDown(repository.close);

    await tester.pumpWidget(
      routerApp(
        store: store,
        repository: repository,
        initialLocation: '/audit',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('员工目录'), findsOneWidget);
    expect(find.text('审计日志'), findsNothing);
  });

  testWidgets('allows an audit deep link when capability is granted', (
    tester,
  ) async {
    const user = CurrentUser(
      id: '00000000-0000-0000-0000-000000000101',
      username: 'hr_admin',
      displayName: '人事管理员',
      employeeId: null,
      employeeNo: null,
      department: null,
      roles: ['hr_admin'],
      capabilities: UserCapabilities(
        canManageEmployees: true,
        canManageDepartments: true,
        canManagePositions: true,
        canViewAudit: true,
        canLogoutAll: true,
      ),
    );
    final store = AuthSessionStore()..markAuthenticated(user);
    final repository = RouterAuthRepository();
    addTearDown(repository.close);

    await tester.pumpWidget(
      routerApp(
        store: store,
        repository: repository,
        initialLocation: '/audit',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('审计日志'), findsOneWidget);
  });

  testWidgets('redirects account admin deep link without account capability', (
    tester,
  ) async {
    final store = AuthSessionStore()..markAuthenticated();
    final repository = RouterAuthRepository();
    addTearDown(repository.close);

    await tester.pumpWidget(
      routerApp(
        store: store,
        repository: repository,
        initialLocation: '/admin/accounts',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('员工目录'), findsOneWidget);
    expect(find.text('账号管理'), findsNothing);
  });
}
