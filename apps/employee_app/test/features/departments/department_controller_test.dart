import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/features/departments/data/department.dart';
import 'package:employee_app/features/departments/data/department_repository.dart';
import 'package:employee_app/features/departments/presentation/department_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDepartmentRepository implements DepartmentRepository {
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

const departments = [
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

void main() {
  test('loads the department hierarchy', () async {
    final repository = FakeDepartmentRepository()..responses.add(departments);
    final container = ProviderContainer(
      overrides: [departmentRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final result = await container.read(departmentControllerProvider.future);

    expect(result, departments);
    expect(repository.requestCount, 1);
  });

  test('retries a failed department request', () async {
    final repository = FakeDepartmentRepository()
      ..responses.add(const Failure.network())
      ..responses.add(departments);
    final container = ProviderContainer(
      overrides: [departmentRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    container.read(departmentControllerProvider);
    await pumpEventQueue(times: 20);
    expect(container.read(departmentControllerProvider).error, isA<Failure>());
    await container.read(departmentControllerProvider.notifier).retry();

    expect(container.read(departmentControllerProvider).value, departments);
    expect(repository.requestCount, 2);
  });
}
