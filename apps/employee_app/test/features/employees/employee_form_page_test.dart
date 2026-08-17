import 'package:employee_app/features/departments/data/department.dart';
import 'package:employee_app/features/departments/data/department_repository.dart';
import 'package:employee_app/features/employees/data/employee.dart';
import 'package:employee_app/features/employees/data/employee_page.dart';
import 'package:employee_app/features/employees/data/employee_repository.dart';
import 'package:employee_app/features/employees/presentation/employee_form_page.dart';
import 'package:employee_app/features/positions/data/position.dart';
import 'package:employee_app/features/positions/data/position_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class FormDepartmentRepository extends DepartmentRepository {
  @override
  Future<List<Department>> fetchDepartments() async => const [
    Department(
      id: 'department-id',
      code: 'ENG',
      name: '研发中心',
      parentId: null,
      status: 'active',
      sortOrder: 10,
    ),
  ];
}

class FormEmployeeRepository extends EmployeeRepository {
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
  }) => throw UnimplementedError();
}

class FormPositionRepository implements PositionRepository {
  @override
  Future<List<Position>> fetchPositions() async => const [];

  @override
  Future<PositionActionResult> activatePosition(String id) =>
      throw UnimplementedError();

  @override
  Future<Position> createPosition(Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<PositionActionResult> deactivatePosition(String id) =>
      throw UnimplementedError();

  @override
  Future<Position> updatePosition(String id, Map<String, dynamic> data) =>
      throw UnimplementedError();
}

void main() {
  testWidgets('dirty employee form asks before discarding changes', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('返回目标')),
        ),
        GoRoute(
          path: '/form',
          builder: (_, _) => const Scaffold(body: EmployeeFormPage()),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          departmentRepositoryProvider.overrideWithValue(
            FormDepartmentRepository(),
          ),
          employeeRepositoryProvider.overrideWithValue(
            FormEmployeeRepository(),
          ),
          positionRepositoryProvider.overrideWithValue(
            FormPositionRepository(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.push('/form');
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('employee_form_name')),
      '尚未保存的姓名',
    );
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.text('放弃未保存更改？'), findsOneWidget);
    expect(find.text('继续编辑'), findsOneWidget);
    expect(find.text('放弃更改'), findsOneWidget);
  });
}
