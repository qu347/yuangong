import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/features/employees/data/employee.dart';
import 'package:employee_app/features/employees/data/employee_page.dart';
import 'package:employee_app/features/employees/data/employee_repository.dart';
import 'package:employee_app/features/employees/presentation/employee_directory_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordedEmployeeRequest {
  const RecordedEmployeeRequest({
    required this.search,
    required this.departmentId,
    required this.status,
    required this.page,
  });

  final String search;
  final String? departmentId;
  final String? status;
  final int page;
}

class FakeEmployeeRepository implements EmployeeRepository {
  final requests = <RecordedEmployeeRequest>[];
  final responses = <Object>[];

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
    requests.add(
      RecordedEmployeeRequest(
        search: search,
        departmentId: departmentId,
        status: status,
        page: page,
      ),
    );
    if (responses.isEmpty) {
      return emptyEmployeePage;
    }
    final response = responses.removeAt(0);
    if (response is EmployeePage) {
      return response;
    }
    throw response;
  }
}

final sampleEmployee = Employee(
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

const emptyEmployeePage = EmployeePage(
  count: 0,
  next: null,
  previous: null,
  results: [],
);

final populatedEmployeePage = EmployeePage(
  count: 1,
  next: 'https://api.example.test/api/v1/employees/?page=2',
  previous: null,
  results: [sampleEmployee],
);

ProviderContainer createEmployeeContainer(FakeEmployeeRepository repository) {
  return ProviderContainer(
    overrides: [employeeRepositoryProvider.overrideWithValue(repository)],
  );
}

Future<void> settleController() => pumpEventQueue(times: 20);

void main() {
  test('loads the initial employee page', () async {
    final repository = FakeEmployeeRepository()
      ..responses.add(populatedEmployeePage);
    final container = createEmployeeContainer(repository);
    addTearDown(container.dispose);

    expect(
      container.read(employeeDirectoryControllerProvider).page.isLoading,
      isTrue,
    );
    await settleController();

    final state = container.read(employeeDirectoryControllerProvider);
    expect(state.page.value?.results.single.fullName, '林知远');
    expect(repository.requests.single.page, 1);
  });

  test('exposes an empty successful page', () async {
    final repository = FakeEmployeeRepository()
      ..responses.add(emptyEmployeePage);
    final container = createEmployeeContainer(repository);
    addTearDown(container.dispose);

    container.read(employeeDirectoryControllerProvider);
    await settleController();

    expect(
      container.read(employeeDirectoryControllerProvider).page.value?.results,
      isEmpty,
    );
  });

  test('exposes failure and retries the same query', () async {
    final repository = FakeEmployeeRepository()
      ..responses.add(const Failure.network())
      ..responses.add(populatedEmployeePage);
    final container = createEmployeeContainer(repository);
    addTearDown(container.dispose);

    container.read(employeeDirectoryControllerProvider);
    await settleController();
    expect(
      container.read(employeeDirectoryControllerProvider).page.error,
      isA<Failure>(),
    );

    container.read(employeeDirectoryControllerProvider.notifier).retry();
    await settleController();

    expect(
      container.read(employeeDirectoryControllerProvider).page.hasValue,
      isTrue,
    );
    expect(repository.requests.length, 2);
  });

  test('debounces search and only requests the final value', () async {
    final repository = FakeEmployeeRepository();
    final container = createEmployeeContainer(repository);
    addTearDown(container.dispose);
    container.read(employeeDirectoryControllerProvider);
    await settleController();
    final controller = container.read(
      employeeDirectoryControllerProvider.notifier,
    );

    controller.setSearch('林');
    controller.setSearch('林知');
    controller.setSearch('林知远');
    await Future<void>.delayed(const Duration(milliseconds: 380));
    await settleController();

    expect(repository.requests.length, 2);
    expect(repository.requests.last.search, '林知远');
    expect(repository.requests.last.page, 1);
  });

  test(
    'paging and filters preserve boundaries and reset to page one',
    () async {
      final repository = FakeEmployeeRepository()
        ..responses.add(populatedEmployeePage)
        ..responses.add(
          EmployeePage(
            count: 1,
            next: null,
            previous: 'https://api.example.test/api/v1/employees/?page=1',
            results: [sampleEmployee],
          ),
        )
        ..responses.add(populatedEmployeePage)
        ..responses.add(populatedEmployeePage);
      final container = createEmployeeContainer(repository);
      addTearDown(container.dispose);
      container.read(employeeDirectoryControllerProvider);
      await settleController();
      final controller = container.read(
        employeeDirectoryControllerProvider.notifier,
      );

      controller.nextPage();
      await settleController();
      expect(repository.requests.last.page, 2);

      controller.setDepartment('00000000-0000-0000-0000-000000000301');
      await settleController();
      expect(repository.requests.last.page, 1);
      expect(repository.requests.last.departmentId, isNotNull);

      controller.setStatus('departed');
      await settleController();
      expect(repository.requests.last.page, 1);
      expect(repository.requests.last.status, 'departed');
    },
  );
}
