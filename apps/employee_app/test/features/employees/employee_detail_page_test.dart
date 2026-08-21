import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/features/attachments/presentation/employee_attachment_section.dart';
import 'package:employee_app/features/authentication/data/current_user.dart';
import 'package:employee_app/features/authentication/presentation/auth_session_store.dart';
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
  officeLocation: '上海 A 座 8F',
  manager: const EmployeeReference(
    id: '00000000-0000-0000-0000-000000000202',
    employeeNo: 'EMP-0009',
    fullName: '直属负责人',
  ),
  description: '负责企业产品体验。',
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

Widget detailHarness(
  DetailEmployeeRepository repository, {
  String? currentEmployeeId,
  bool canManage = false,
}) {
  final store = AuthSessionStore();
  store.markAuthenticated(
    CurrentUser(
      id: 'user-id',
      username: canManage ? 'hr.manager' : 'employee.viewer',
      displayName: canManage ? '人事管理员' : '员工',
      employeeId: currentEmployeeId,
      employeeNo: currentEmployeeId == null ? null : 'EMP-0001',
      department: null,
      roles: [canManage ? 'hr_admin' : 'employee'],
      capabilities: canManage
          ? const UserCapabilities(
              canManageEmployees: true,
              canManageDepartments: true,
              canManagePositions: true,
              canViewAudit: true,
              canLogoutAll: true,
            )
          : const UserCapabilities.none(),
    ),
  );
  return ProviderScope(
    overrides: [
      employeeRepositoryProvider.overrideWithValue(repository),
      authSessionStoreProvider.overrideWithValue(store),
      currentEmployeeIdProvider.overrideWithValue(currentEmployeeId),
    ],
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
  testWidgets('employee avatar prefers a configured network image', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EmployeeAvatar(
          fullName: '林知远',
          avatarUrl: 'https://assets.example.test/avatar.png',
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      image.image,
      isA<NetworkImage>().having(
        (provider) => provider.url,
        'url',
        'https://assets.example.test/avatar.png',
      ),
    );
    expect(find.text('林'), findsNothing);
  });

  testWidgets('employee avatar falls back to initial after image failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EmployeeAvatar(
          fullName: '林知远',
          avatarUrl: 'https://invalid.invalid/avatar.png',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('林'), findsOneWidget);
  });

  testWidgets('employee avatar uses initial when url is empty', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EmployeeAvatar(fullName: '林知远', avatarUrl: ''),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.text('林'), findsOneWidget);
  });

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
      '上海 A 座 8F',
      '直属负责人',
      '负责企业产品体验。',
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

  testWidgets('employee self sees the attachment section', (tester) async {
    final repository = DetailEmployeeRepository(detailEmployee);

    await tester.pumpWidget(
      detailHarness(repository, currentEmployeeId: detailEmployee.id),
    );
    await tester.pumpAndSettle();

    expect(find.text('员工附件'), findsOneWidget);
  });

  testWidgets('employee viewing another profile sees no attachment section', (
    tester,
  ) async {
    final repository = DetailEmployeeRepository(detailEmployee);

    await tester.pumpWidget(
      detailHarness(
        repository,
        currentEmployeeId: '20000000-0000-0000-0000-000000000999',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('员工附件'), findsNothing);
  });

  testWidgets('employee manager sees the attachment section', (tester) async {
    final repository = DetailEmployeeRepository(detailEmployee);

    await tester.pumpWidget(detailHarness(repository, canManage: true));
    await tester.pumpAndSettle();

    expect(find.text('员工附件'), findsOneWidget);
  });
}
