import 'package:employee_app/features/departments/data/organization_tree_repository.dart';
import 'package:employee_app/features/departments/presentation/organization_tree_page.dart';
import 'package:employee_app/features/employees/data/employee.dart';
import 'package:employee_app/features/employees/data/employee_page.dart';
import 'package:employee_app/features/employees/data/employee_repository.dart';
import 'package:employee_app/features/notifications/data/notification_repository.dart';
import 'package:employee_app/features/notifications/presentation/notification_page.dart';
import 'package:employee_app/features/search/data/global_search_repository.dart';
import 'package:employee_app/features/search/presentation/global_search_page.dart';
import 'package:employee_app/features/statistics/data/hr_statistics_repository.dart';
import 'package:employee_app/features/statistics/presentation/hr_statistics_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class EmptyTreeRepository implements OrganizationTreeRepository {
  @override
  Future<List<OrganizationTreeNode>> fetchTree() async => const [];
}

class MembersTreeRepository implements OrganizationTreeRepository {
  @override
  Future<List<OrganizationTreeNode>> fetchTree() async => const [
    OrganizationTreeNode(
      id: '00000000-0000-0000-0000-000000000302',
      code: 'ENG',
      name: '研发部',
      status: 'active',
      employeeCount: 1,
      children: [],
    ),
  ];
}

class MembersEmployeeRepository extends EmployeeRepository {
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
  }) async {
    if (departmentId != '00000000-0000-0000-0000-000000000302') {
      return const EmployeePage(
        count: 0,
        next: null,
        previous: null,
        results: [],
      );
    }
    return EmployeePage(
      count: 1,
      next: null,
      previous: null,
      results: [
        Employee(
          id: '00000000-0000-0000-0000-000000000201',
          employeeNo: 'EMP-0001',
          fullName: '林知远',
          workEmail: 'lin.zhiyuan@example.test',
          workPhone: '010-5550-1001',
          department: const DirectoryReference(
            id: '00000000-0000-0000-0000-000000000302',
            code: 'ENG',
            name: '研发部',
          ),
          position: const DirectoryReference(
            id: '00000000-0000-0000-0000-000000000401',
            code: 'SWE',
            name: '软件工程师',
          ),
          employmentStatus: 'active',
          hireDate: DateTime(2023, 5, 8),
        ),
      ],
    );
  }
}

class PageSearchRepository implements GlobalSearchRepository {
  @override
  Future<GlobalSearchPageData> search(
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async {
    return const GlobalSearchPageData(
      count: 3,
      results: [
        GlobalSearchResult(
          type: SearchResultType.employee,
          id: '00000000-0000-0000-0000-000000000201',
          title: '林知远',
          subtitle: 'EMP-0001 · lin.zhiyuan@example.test · 研发中心',
        ),
        GlobalSearchResult(
          type: SearchResultType.department,
          id: '00000000-0000-0000-0000-000000000301',
          title: '研发中心',
          subtitle: 'ENG',
        ),
        GlobalSearchResult(
          type: SearchResultType.position,
          id: '00000000-0000-0000-0000-000000000401',
          title: '软件工程师',
          subtitle: 'ENG-SWE · 研发中心',
        ),
      ],
    );
  }
}

class PageNotificationRepository implements NotificationRepository {
  bool marked = false;

  @override
  Future<NotificationPageData> fetchNotifications({
    int page = 1,
    int pageSize = 20,
  }) async {
    return NotificationPageData(
      count: 1,
      unreadCount: 1,
      results: [
        AppNotification(
          id: '00000000-0000-0000-0000-000000000501',
          title: '系统通知',
          content: '系统维护完成。',
          read: false,
          createdAt: DateTime.utc(2026, 8, 20),
        ),
      ],
    );
  }

  @override
  Future<AppNotification> markRead(String id) async {
    marked = true;
    return AppNotification(
      id: id,
      title: '系统通知',
      content: '系统维护完成。',
      read: true,
      createdAt: DateTime.utc(2026, 8, 20),
    );
  }
}

class PageHrStatisticsRepository implements HrStatisticsRepository {
  @override
  Future<HrStatistics> fetchStatistics() async => const HrStatistics(
    employeeTotal: 100,
    positionTotal: 30,
    departmentHeadcount: [
      DepartmentHeadcount(
        id: '00000000-0000-0000-0000-000000000301',
        name: '研发中心',
        count: 42,
      ),
      DepartmentHeadcount(
        id: '00000000-0000-0000-0000-000000000302',
        name: '人力资源部',
        count: 12,
      ),
    ],
    hireTrend: [
      HireTrendPoint(month: '2026-06', count: 5),
      HireTrendPoint(month: '2026-07', count: 8),
    ],
    genderDistribution: [
      StatisticsCount(label: 'female', count: 46),
      StatisticsCount(label: 'male', count: 54),
    ],
    ageDistribution: [StatisticsCount(label: '30_39', count: 61)],
  );
}

void main() {
  testWidgets('organization tree loads members for the selected department', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          organizationTreeRepositoryProvider.overrideWithValue(
            MembersTreeRepository(),
          ),
          employeeRepositoryProvider.overrideWithValue(
            MembersEmployeeRepository(),
          ),
        ],
        child: const MaterialApp(home: OrganizationTreePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('研发部'));
    await tester.pumpAndSettle();

    expect(find.text('研发部成员'), findsOneWidget);
    expect(find.text('林知远'), findsOneWidget);
    expect(find.text('EMP-0001'), findsOneWidget);
    expect(find.text('lin.zhiyuan@example.test'), findsOneWidget);
    expect(find.text('软件工程师'), findsOneWidget);
  });

  testWidgets('hr statistics renders organization trends and people analysis', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hrStatisticsRepositoryProvider.overrideWithValue(
            PageHrStatisticsRepository(),
          ),
        ],
        child: const MaterialApp(home: HrStatisticsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('HR 统计'), findsOneWidget);
    expect(find.text('部门人数统计'), findsOneWidget);
    expect(find.text('岗位统计'), findsOneWidget);
    expect(find.text('入职趋势'), findsOneWidget);
    expect(find.text('基础人员分析'), findsOneWidget);
    expect(find.text('研发中心'), findsOneWidget);
    expect(find.text('42 人'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('2026-07'), findsOneWidget);
  });

  testWidgets('organization tree exposes an empty state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          organizationTreeRepositoryProvider.overrideWithValue(
            EmptyTreeRepository(),
          ),
        ],
        child: const MaterialApp(home: OrganizationTreePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无组织架构'), findsOneWidget);
  });

  testWidgets('global search submits a keyword and renders a typed result', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          globalSearchRepositoryProvider.overrideWithValue(
            PageSearchRepository(),
          ),
        ],
        child: const MaterialApp(home: GlobalSearchPage()),
      ),
    );
    await tester.enterText(find.byType(SearchBar), '林知远');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('员工'), findsOneWidget);
    expect(find.text('部门'), findsOneWidget);
    expect(find.text('岗位'), findsOneWidget);
    expect(find.text('林知远'), findsWidgets);
    expect(
      find.text('EMP-0001 · lin.zhiyuan@example.test · 研发中心'),
      findsOneWidget,
    );
    expect(find.text('研发中心'), findsOneWidget);
    expect(find.text('软件工程师'), findsOneWidget);
  });

  testWidgets(
    'notification page marks an unread item without duplicate submission',
    (tester) async {
      final repository = PageNotificationRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: NotificationPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('未读 1 条，共 1 条'), findsOneWidget);
      await tester.tap(find.text('标为已读'));
      await tester.pumpAndSettle();
      expect(repository.marked, isTrue);
      expect(find.text('已读'), findsOneWidget);
    },
  );
}
