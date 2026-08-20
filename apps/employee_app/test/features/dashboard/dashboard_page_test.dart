import 'package:employee_app/core/config/app_config.dart';
import 'package:employee_app/features/authentication/data/current_user.dart';
import 'package:employee_app/features/authentication/presentation/auth_session_store.dart';
import 'package:employee_app/features/dashboard/data/dashboard_summary.dart';
import 'package:employee_app/features/dashboard/presentation/dashboard_controller.dart';
import 'package:employee_app/features/dashboard/presentation/dashboard_page.dart';
import 'package:employee_app/features/health/data/health_response.dart';
import 'package:employee_app/features/health/presentation/health_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows hr statistics shortcut only for permitted roles', (
    tester,
  ) async {
    const user = CurrentUser(
      id: '00000000-0000-0000-0000-000000000101',
      username: 'hr.statistics',
      displayName: '统计管理员',
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(store),
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
          dashboardControllerProvider.overrideWith(
            () => _TestDashboardController(),
          ),
        ],
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('HR统计'), findsOneWidget);
  });

  testWidgets('shows healthy backend and environment details', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
          dashboardControllerProvider.overrideWith(
            () => _TestDashboardController(),
          ),
        ],
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('后端连接正常'), findsOneWidget);
    expect(find.text('员工总数'), findsOneWidget);
    expect(find.text('在职员工'), findsOneWidget);
    expect(find.text('部门数量'), findsOneWidget);
    expect(find.text('test'), findsOneWidget);
    expect(find.text('https://api.example.test/api/v1'), findsOneWidget);
  });
}

class _TestDashboardController extends DashboardController {
  @override
  Future<DashboardSummary> build() async => const DashboardSummary(
    employeeTotal: 100,
    activeEmployee: 90,
    departedEmployee: 10,
    departmentTotal: 8,
    positionTotal: 30,
    recentOperations: [],
  );
}
