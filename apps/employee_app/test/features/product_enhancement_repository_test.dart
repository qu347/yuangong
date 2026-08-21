import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/core/network/api_endpoints.dart';
import 'package:employee_app/features/departments/data/organization_tree_repository.dart';
import 'package:employee_app/features/notifications/data/notification_repository.dart';
import 'package:employee_app/features/search/data/global_search_repository.dart';
import 'package:employee_app/features/statistics/data/hr_statistics_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockProductApiClient extends Mock implements ApiClient {}

void main() {
  late MockProductApiClient client;

  setUp(() => client = MockProductApiClient());

  test(
    'global search parses paginated employee department and position results',
    () async {
      when(
        () => client.getMap(
          ApiEndpoints.globalSearch,
          queryParameters: {'q': '研发', 'page': 1, 'page_size': 20},
        ),
      ).thenAnswer(
        (_) async => {
          'count': 2,
          'next': null,
          'previous': null,
          'results': [
            {
              'type': 'employee',
              'id': '00000000-0000-0000-0000-000000000201',
              'title': '林知远',
              'subtitle': 'EMP-0001 · lin.zhiyuan@example.test · 研发中心',
            },
            {
              'type': 'department',
              'id': '00000000-0000-0000-0000-000000000301',
              'title': '研发中心',
              'subtitle': 'ENG',
            },
          ],
        },
      );

      final page = await NetworkGlobalSearchRepository(client).search('研发');

      expect(page.count, 2);
      expect(page.results.first.type, SearchResultType.employee);
      expect(page.results.first.subtitle, contains('lin.zhiyuan@example.test'));
      expect(page.results.last.title, '研发中心');
    },
  );

  test(
    'hr statistics parses organization trends and people analysis',
    () async {
      when(() => client.getMap(ApiEndpoints.hrStatistics)).thenAnswer(
        (_) async => {
          'employee_total': 100,
          'position_total': 30,
          'department_headcount': [
            {
              'department_id': '00000000-0000-0000-0000-000000000301',
              'department_name': '研发中心',
              'count': 42,
            },
          ],
          'hire_trend': [
            {'month': '2026-07', 'count': 8},
          ],
          'gender_distribution': [
            {'label': 'female', 'count': 46},
            {'label': 'male', 'count': 54},
          ],
          'age_distribution': [
            {'label': '30_39', 'count': 61},
          ],
        },
      );

      final statistics = await NetworkHrStatisticsRepository(
        client,
      ).fetchStatistics();

      expect(statistics.employeeTotal, 100);
      expect(statistics.positionTotal, 30);
      expect(statistics.departmentHeadcount.single.name, '研发中心');
      expect(statistics.departmentHeadcount.single.count, 42);
      expect(statistics.hireTrend.single.month, '2026-07');
      expect(statistics.genderDistribution.last.count, 54);
      expect(statistics.ageDistribution.single.label, '30_39');
    },
  );

  test('organization tree preserves children counts and status', () async {
    when(() => client.getList(ApiEndpoints.departmentTree)).thenAnswer(
      (_) async => [
        {
          'id': '00000000-0000-0000-0000-000000000301',
          'code': 'HQ',
          'name': '总部',
          'status': 'active',
          'employee_count': 0,
          'children': [
            {
              'id': '00000000-0000-0000-0000-000000000302',
              'code': 'ENG',
              'name': '研发部',
              'status': 'active',
              'employee_count': 12,
              'children': <dynamic>[],
            },
          ],
        },
      ],
    );

    final tree = await NetworkOrganizationTreeRepository(client).fetchTree();

    expect(tree.single.children.single.employeeCount, 12);
    expect(tree.single.children.single.isActive, isTrue);
  });

  test(
    'notification repository parses unread count and sends idempotent read patch',
    () async {
      const id = '00000000-0000-0000-0000-000000000501';
      when(
        () => client.getMap(
          ApiEndpoints.notifications,
          queryParameters: {'page': 1, 'page_size': 20},
        ),
      ).thenAnswer(
        (_) async => {
          'count': 1,
          'unread_count': 1,
          'next': null,
          'previous': null,
          'results': [
            {
              'id': id,
              'title': '系统通知',
              'content': '系统维护完成。',
              'read': false,
              'created_at': '2026-08-20T08:00:00Z',
            },
          ],
        },
      );
      when(
        () => client.patchMap('${ApiEndpoints.notifications}$id/read/'),
      ).thenAnswer(
        (_) async => {
          'id': id,
          'title': '系统通知',
          'content': '系统维护完成。',
          'read': true,
          'created_at': '2026-08-20T08:00:00Z',
        },
      );
      final repository = NetworkNotificationRepository(client);

      final page = await repository.fetchNotifications();
      final read = await repository.markRead(id);

      expect(page.unreadCount, 1);
      expect(page.results.single.read, isFalse);
      expect(read.read, isTrue);
    },
  );
}
