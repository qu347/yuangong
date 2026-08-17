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
import 'package:integration_test/integration_test.dart';

const integrationUser = CurrentUser(
  id: '00000000-0000-0000-0000-000000000101',
  username: 'integration_test',
  displayName: '集成测试用户',
  employeeId: null,
  employeeNo: null,
  department: null,
  roles: [],
);

class IntegrationAuthRepository implements AuthRepository {
  @override
  Stream<void> get authenticationLost => const Stream.empty();

  @override
  Future<CurrentUser> login({
    required String username,
    required String password,
  }) async => integrationUser;

  @override
  Future<void> logout() async {}

  @override
  Future<int> logoutAll() async => 0;

  @override
  Future<CurrentUser?> restoreSession() async => integrationUser;
}

class IntegrationEmployeeRepository extends EmployeeRepository {
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

class IntegrationDepartmentRepository extends DepartmentRepository {
  @override
  Future<List<Department>> fetchDepartments() async => const [];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starts without contacting a real backend', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(IntegrationAuthRepository()),
          authSessionStoreProvider.overrideWithValue(AuthSessionStore()),
          employeeRepositoryProvider.overrideWithValue(
            IntegrationEmployeeRepository(),
          ),
          departmentRepositoryProvider.overrideWithValue(
            IntegrationDepartmentRepository(),
          ),
          appConfigProvider.overrideWithValue(
            const AppConfig(
              appEnvironment: 'integration-test',
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

    expect(find.text('员工目录'), findsOneWidget);
    expect(find.text('没有符合条件的员工'), findsOneWidget);
  });
}
