import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/features/departments/data/department.dart';
import 'package:employee_app/features/departments/data/department_repository.dart';
import 'package:employee_app/features/departments/presentation/department_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const pageDepartments = [
  Department(
    id: '00000000-0000-0000-0000-000000000301',
    code: 'HQ',
    name: '企业总部',
    parentId: null,
    status: 'active',
    sortOrder: 10,
  ),
  Department(
    id: '00000000-0000-0000-0000-000000000302',
    code: 'ENG',
    name: '研发中心',
    parentId: '00000000-0000-0000-0000-000000000301',
    status: 'active',
    sortOrder: 20,
  ),
];

class PageDepartmentRepository extends DepartmentRepository {
  final responses = <Object>[];
  int requestCount = 0;

  @override
  Future<List<Department>> fetchDepartments() async {
    requestCount += 1;
    final response = responses.removeAt(0);
    if (response is List<Department>) {
      return response;
    }
    throw response;
  }
}

Widget departmentHarness(PageDepartmentRepository repository) {
  return ProviderScope(
    overrides: [departmentRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(home: Scaffold(body: DepartmentPage())),
  );
}

void main() {
  testWidgets('shows a read-only department hierarchy', (tester) async {
    final repository = PageDepartmentRepository()
      ..responses.add(pageDepartments);

    await tester.pumpWidget(departmentHarness(repository));
    await tester.pumpAndSettle();

    expect(find.text('企业总部'), findsOneWidget);
    expect(find.text('研发中心'), findsOneWidget);
    expect(find.text('HQ'), findsOneWidget);
    expect(find.text('ENG'), findsOneWidget);
    expect(find.text('启用'), findsNWidgets(2));
    final childPadding = tester.widget<Padding>(
      find.byKey(const Key('department_00000000-0000-0000-0000-000000000302')),
    );
    expect(
      childPadding.padding.resolve(TextDirection.ltr).left,
      greaterThan(16),
    );
  });

  testWidgets('shows an empty department state', (tester) async {
    final repository = PageDepartmentRepository()
      ..responses.add(<Department>[]);

    await tester.pumpWidget(departmentHarness(repository));
    await tester.pumpAndSettle();

    expect(find.text('暂无部门数据'), findsOneWidget);
  });

  testWidgets('shows department failure and retries', (tester) async {
    final repository = PageDepartmentRepository()
      ..responses.add(const Failure.network())
      ..responses.add(pageDepartments);

    await tester.pumpWidget(departmentHarness(repository));
    await tester.pumpAndSettle();
    expect(find.text('无法连接后端服务，请检查服务是否启动。'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('企业总部'), findsOneWidget);
    expect(repository.requestCount, 2);
  });
}
