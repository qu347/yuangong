import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/core/network/api_endpoints.dart';
import 'package:employee_app/features/departments/data/department_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDepartmentApiClient extends Mock implements ApiClient {}

void main() {
  late MockDepartmentApiClient apiClient;
  late NetworkDepartmentRepository repository;

  setUp(() {
    apiClient = MockDepartmentApiClient();
    repository = NetworkDepartmentRepository(apiClient);
  });

  test('parses the flat department hierarchy from the API', () async {
    when(() => apiClient.getList(ApiEndpoints.departments)).thenAnswer(
      (_) async => [
        {
          'id': '00000000-0000-0000-0000-000000000301',
          'code': 'HQ',
          'name': '企业总部',
          'parent': null,
          'status': 'active',
          'sort_order': 10,
        },
        {
          'id': '00000000-0000-0000-0000-000000000302',
          'code': 'ENG',
          'name': '研发中心',
          'parent': '00000000-0000-0000-0000-000000000301',
          'status': 'active',
          'sort_order': 20,
        },
      ],
    );

    final departments = await repository.fetchDepartments();

    expect(departments.length, 2);
    expect(departments.first.parentId, isNull);
    expect(departments.last.parentId, departments.first.id);
    expect(departments.last.isActive, isTrue);
  });

  test('maps malformed department data into a safe data failure', () async {
    when(() => apiClient.getList(ApiEndpoints.departments)).thenAnswer(
      (_) async => [
        {'id': 'invalid'},
      ],
    );

    await expectLater(
      repository.fetchDepartments(),
      throwsA(
        isA<Failure>().having((error) => error.type, 'type', FailureType.data),
      ),
    );
  });

  test('creates, updates, and deactivates a department', () async {
    const departmentJson = <String, dynamic>{
      'id': '00000000-0000-0000-0000-000000000301',
      'code': 'HQ',
      'name': '企业总部',
      'parent': null,
      'status': 'active',
      'sort_order': 10,
    };
    when(
      () =>
          apiClient.postMap(ApiEndpoints.departments, data: any(named: 'data')),
    ).thenAnswer((_) async => departmentJson);
    when(
      () => apiClient.patchMap(
        '${ApiEndpoints.departments}${departmentJson['id']}/',
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => {...departmentJson, 'name': '企业总部（更新）'});
    when(
      () => apiClient.postMap(
        '${ApiEndpoints.departments}${departmentJson['id']}/deactivate/',
        data: const {},
      ),
    ).thenAnswer(
      (_) async => {
        'department': {...departmentJson, 'status': 'inactive'},
        'changed': true,
      },
    );

    final created = await repository.createDepartment({
      'code': 'HQ',
      'name': '企业总部',
    });
    final updated = await repository.updateDepartment(created.id, {
      'name': '企业总部（更新）',
    });
    final deactivated = await repository.deactivateDepartment(created.id);

    expect(updated.name, '企业总部（更新）');
    expect(deactivated.changed, isTrue);
    expect(deactivated.department.isActive, isFalse);
  });
}
