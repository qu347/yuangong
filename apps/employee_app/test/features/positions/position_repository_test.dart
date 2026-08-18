import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/core/network/api_endpoints.dart';
import 'package:employee_app/features/positions/data/position_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPositionApiClient extends Mock implements ApiClient {}

const positionJson = <String, dynamic>{
  'id': '00000000-0000-0000-0000-000000000401',
  'code': 'ENG-SWE',
  'name': '软件工程师',
  'department': {
    'id': '00000000-0000-0000-0000-000000000301',
    'code': 'ENG',
    'name': '研发中心',
  },
  'status': 'active',
};

void main() {
  test('loads and manages positions through the shared API client', () async {
    final apiClient = MockPositionApiClient();
    final repository = NetworkPositionRepository(apiClient);
    when(
      () => apiClient.getList(ApiEndpoints.positions),
    ).thenAnswer((_) async => [positionJson]);
    when(
      () => apiClient.postMap(ApiEndpoints.positions, data: any(named: 'data')),
    ).thenAnswer((_) async => positionJson);
    when(
      () => apiClient.postMap(
        '${ApiEndpoints.positions}${positionJson['id']}/deactivate/',
        data: const {},
      ),
    ).thenAnswer(
      (_) async => {
        'position': {...positionJson, 'status': 'inactive'},
        'changed': true,
      },
    );

    final positions = await repository.fetchPositions();
    final created = await repository.createPosition({
      'code': 'ENG-SWE',
      'name': '软件工程师',
      'department': '00000000-0000-0000-0000-000000000301',
    });
    final deactivated = await repository.deactivatePosition(created.id);

    expect(positions.single.department.name, '研发中心');
    expect(deactivated.changed, isTrue);
    expect(deactivated.position.isActive, isFalse);
  });
}
