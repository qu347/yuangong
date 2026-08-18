import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/core/network/api_endpoints.dart';
import 'package:employee_app/features/audit/data/audit_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuditApiClient extends Mock implements ApiClient {}

void main() {
  test('parses paginated audit events and sends safe filters', () async {
    final apiClient = MockAuditApiClient();
    final repository = NetworkAuditRepository(apiClient);
    when(
      () => apiClient.getMap(
        ApiEndpoints.auditEvents,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => {
        'count': 1,
        'next': null,
        'previous': null,
        'results': [
          {
            'id': '00000000-0000-0000-0000-000000000501',
            'actor': {
              'id': '00000000-0000-0000-0000-000000000101',
              'username': 'hr_admin',
            },
            'action': 'update',
            'resource_type': 'employee',
            'resource_id': '00000000-0000-0000-0000-000000000201',
            'resource_label': 'EMP-0001 · 林知远',
            'changes': {
              'full_name': {'from': '旧名称', 'to': '林知远'},
            },
            'source': 'api',
            'request_id': null,
            'created_at': '2026-08-17T15:30:00+08:00',
          },
        ],
      },
    );

    final page = await repository.fetchAuditEvents(
      action: 'update',
      resourceType: 'employee',
      page: 2,
    );

    expect(page.count, 1);
    expect(page.results.single.actorUsername, 'hr_admin');
    expect(page.results.single.changes.keys, ['full_name']);
    verify(
      () => apiClient.getMap(
        ApiEndpoints.auditEvents,
        queryParameters: {
          'action': 'update',
          'resource_type': 'employee',
          'page': 2,
          'page_size': 20,
          'ordering': '-created_at',
        },
      ),
    ).called(1);
  });
}
