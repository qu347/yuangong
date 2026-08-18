import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/features/employees/data/employee.dart';
import 'package:employee_app/features/employees/data/employee_page.dart';
import 'package:employee_app/features/employees/data/employee_repository.dart';
import 'package:employee_app/features/employees/presentation/employee_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final detailEmployee = Employee(
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

class DetailEmployeeRepository extends EmployeeRepository {
  DetailEmployeeRepository(this.response);

  Object response;
  int requestCount = 0;

  @override
  Future<Employee> fetchEmployee(String id) async {
    requestCount += 1;
    final current = response;
    if (current is Employee) {
      return current;
    }
    throw current;
  }

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

Widget detailHarness(DetailEmployeeRepository repository) {
  return ProviderScope(
    overrides: [employeeRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(
      home: Scaffold(
        body: EmployeeDetailPage(
          employeeId: '00000000-0000-0000-0000-000000000201',
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows only directory-safe employee detail fields', (
    tester,
  ) async {
    final repository = DetailEmployeeRepository(detailEmployee);

    await tester.pumpWidget(detailHarness(repository));
    await tester.pumpAndSettle();

    for (final text in [
      '林知远',
      'EMP-0001',
      'lin.zhiyuan@example.test',
      '010-5550-1001',
      '研发中心',
      '软件工程师',
      '在职',
      '2023-05-08',
    ]) {
      expect(find.text(text), findsWidgets);
    }
    expect(find.textContaining('工资'), findsNothing);
    expect(find.textContaining('身份证'), findsNothing);
    expect(find.textContaining('银行卡'), findsNothing);
    expect(find.textContaining('家庭住址'), findsNothing);
  });

  testWidgets('shows detail failure and retries', (tester) async {
    final repository = DetailEmployeeRepository(const Failure.network());

    await tester.pumpWidget(detailHarness(repository));
    await tester.pumpAndSettle();
    expect(find.text('无法连接后端服务，请检查服务是否启动。'), findsOneWidget);

    repository.response = detailEmployee;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('林知远'), findsWidgets);
    expect(repository.requestCount, 2);
  });
}
