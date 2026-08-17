import 'package:employee_app/app/app.dart';
import 'package:employee_app/core/config/app_config.dart';
import 'package:employee_app/features/authentication/data/auth_repository.dart';
import 'package:employee_app/features/authentication/data/current_user.dart';
import 'package:employee_app/features/authentication/presentation/auth_session_store.dart';
import 'package:employee_app/features/departments/data/department.dart';
import 'package:employee_app/features/departments/data/department_repository.dart';
import 'package:employee_app/features/employees/data/employee.dart';
import 'package:employee_app/features/employees/data/employee_page.dart';
import 'package:employee_app/features/employees/data/employee_repository.dart';
import 'package:employee_app/features/health/data/health_response.dart';
import 'package:employee_app/features/health/presentation/health_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const smokeTestUser = CurrentUser(
  id: '00000000-0000-0000-0000-000000000101',
  username: 'smoke_test',
  displayName: '冒烟用户',
  employeeId: null,
  employeeNo: null,
  department: null,
  roles: [],
);

class SmokeAuthRepository implements AuthRepository {
  @override
  Stream<void> get authenticationLost => const Stream.empty();

  @override
  Future<CurrentUser> login({
    required String username,
    required String password,
  }) async => smokeTestUser;

  @override
  Future<void> logout() async {}

  @override
  Future<CurrentUser?> restoreSession() async => smokeTestUser;
}

class SmokeEmployeeRepository implements EmployeeRepository {
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

class SmokeDepartmentRepository implements DepartmentRepository {
  @override
  Future<List<Department>> fetchDepartments() async => const [];
}

void main() {
  testWidgets('authenticated application starts on the employee directory', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(SmokeAuthRepository()),
          authSessionStoreProvider.overrideWithValue(AuthSessionStore()),
          employeeRepositoryProvider.overrideWithValue(
            SmokeEmployeeRepository(),
          ),
          departmentRepositoryProvider.overrideWithValue(
            SmokeDepartmentRepository(),
          ),
          appConfigProvider.overrideWithValue(
            const AppConfig(
              appEnvironment: 'test',
              apiBaseUrl: 'https://api.example.test/api/v1',
            ),
          ),
          healthControllerProvider.overrideWith(
            (ref) async => const HealthResponse(
              status: 'ok',
              service: 'employee-api',
              version: '0.1.0',
              database: 'ok',
            ),
          ),
        ],
        child: const EmployeeApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('通讯录'), findsWidgets);
    expect(find.text('企业员工管理系统'), findsOneWidget);
  });
}
