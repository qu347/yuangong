import 'dart:async';

import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/features/departments/data/department.dart';
import 'package:employee_app/features/departments/data/department_repository.dart';
import 'package:employee_app/features/employees/data/employee.dart';
import 'package:employee_app/features/employees/data/employee_page.dart';
import 'package:employee_app/features/employees/data/employee_repository.dart';
import 'package:employee_app/features/employees/presentation/employee_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final listEmployee = Employee(
  id: '00000000-0000-0000-0000-000000000201',
  employeeNo: 'EMP-0001',
  fullName: '林知远',
  workEmail: 'lin.zhiyuan@example.test',
  workPhone: '010-5550-1001',
  department: const DirectoryReference(
    id: '00000000-0000-0000-0000-000000000301',
    code: 'ENG',
    name: '研发中心',
  ),
  position: const DirectoryReference(
    id: '00000000-0000-0000-0000-000000000401',
    code: 'ENG-SWE',
    name: '软件工程师',
  ),
  employmentStatus: 'active',
  hireDate: DateTime(2023, 5, 8),
);

final listPage = EmployeePage(
  count: 1,
  next: null,
  previous: null,
  results: [listEmployee],
);

class PageEmployeeRepository extends EmployeeRepository {
  final responses = <Object>[];
  Completer<EmployeePage>? pending;
  int requestCount = 0;
  String lastSearch = '';

  @override
  Future<Employee> fetchEmployee(String id) async => listEmployee;

  @override
  Future<EmployeePage> fetchEmployees({
    String search = '',
    String? departmentId,
    String? status,
    int page = 1,
    int pageSize = 20,
    String ordering = 'employee_no',
  }) async {
    requestCount += 1;
    lastSearch = search;
    final pendingRequest = pending;
    if (pendingRequest != null) {
      return pendingRequest.future;
    }
    final response = responses.removeAt(0);
    if (response is EmployeePage) {
      return response;
    }
    throw response;
  }
}

class PageDepartmentRepository extends DepartmentRepository {
  @override
  Future<List<Department>> fetchDepartments() async => const [
    Department(
      id: '00000000-0000-0000-0000-000000000301',
      code: 'ENG',
      name: '研发中心',
      parentId: null,
      status: 'active',
      sortOrder: 10,
    ),
  ];
}

Widget employeePageHarness(PageEmployeeRepository employeeRepository) {
  return ProviderScope(
    overrides: [
      employeeRepositoryProvider.overrideWithValue(employeeRepository),
      departmentRepositoryProvider.overrideWithValue(
        PageDepartmentRepository(),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: EmployeeListPage())),
  );
}

void setTestSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}

void main() {
  testWidgets('shows employee loading state', (tester) async {
    final repository = PageEmployeeRepository()
      ..pending = Completer<EmployeePage>();

    await tester.pumpWidget(employeePageHarness(repository));
    await tester.pump();

    expect(find.text('正在加载员工目录'), findsOneWidget);
    repository.pending!.complete(listPage);
    await tester.pumpAndSettle();
  });

  testWidgets('shows compact employee cards and filter controls', (
    tester,
  ) async {
    setTestSize(tester, const Size(700, 900));
    final repository = PageEmployeeRepository()..responses.add(listPage);

    await tester.pumpWidget(employeePageHarness(repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('employee_search')), findsOneWidget);
    expect(find.byKey(const Key('employee_department_filter')), findsOneWidget);
    expect(find.byKey(const Key('employee_status_filter')), findsOneWidget);
    expect(find.byKey(const Key('employee_card_EMP-0001')), findsOneWidget);
    expect(find.text('林知远'), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
  });

  testWidgets('shows a desktop employee table at the desktop breakpoint', (
    tester,
  ) async {
    setTestSize(tester, const Size(1200, 850));
    final repository = PageEmployeeRepository()..responses.add(listPage);

    await tester.pumpWidget(employeePageHarness(repository));
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('EMP-0001'), findsOneWidget);
    expect(find.text('研发中心'), findsOneWidget);
  });

  testWidgets('shows an empty employee state', (tester) async {
    final repository = PageEmployeeRepository()
      ..responses.add(
        const EmployeePage(count: 0, next: null, previous: null, results: []),
      );

    await tester.pumpWidget(employeePageHarness(repository));
    await tester.pumpAndSettle();

    expect(find.text('没有符合条件的员工'), findsOneWidget);
  });

  testWidgets('shows employee failure and retries successfully', (
    tester,
  ) async {
    final repository = PageEmployeeRepository()
      ..responses.add(const Failure.network())
      ..responses.add(listPage);

    await tester.pumpWidget(employeePageHarness(repository));
    await tester.pumpAndSettle();
    expect(find.text('无法连接后端服务，请检查服务是否启动。'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('林知远'), findsOneWidget);
    expect(repository.requestCount, 2);
  });

  testWidgets('search input reaches the debounced controller query', (
    tester,
  ) async {
    final repository = PageEmployeeRepository()
      ..responses.add(listPage)
      ..responses.add(listPage);

    await tester.pumpWidget(employeePageHarness(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('employee_search')), '林知远');
    await tester.pump(const Duration(milliseconds: 380));
    await tester.pumpAndSettle();

    expect(repository.lastSearch, '林知远');
  });
}
