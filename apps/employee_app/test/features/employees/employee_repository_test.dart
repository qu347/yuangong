import 'package:employee_app/core/errors/app_exception.dart';
import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/core/network/api_endpoints.dart';
import 'package:employee_app/features/employees/data/employee_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockEmployeeApiClient extends Mock implements ApiClient {}

const employeeJson = <String, dynamic>{
  'id': '00000000-0000-0000-0000-000000000201',
  'employee_no': 'EMP-0001',
  'full_name': '林知远',
  'work_email': 'lin.zhiyuan@example.test',
  'work_phone': '010-5550-1001',
  'department': {
    'id': '00000000-0000-0000-0000-000000000301',
    'code': 'ENG',
    'name': '研发中心',
  },
  'position': {
    'id': '00000000-0000-0000-0000-000000000401',
    'code': 'ENG-SWE',
    'name': '软件工程师',
  },
  'employment_status': 'active',
  'hire_date': '2023-05-08',
  'avatar_url': 'https://assets.example.test/avatar.png',
  'gender': 'female',
  'birthday': '1992-06-08',
  'office_location': '上海 A 座 8F',
  'manager': {
    'id': '00000000-0000-0000-0000-000000000202',
    'employee_no': 'EMP-0009',
    'full_name': '直属负责人',
  },
  'description': '负责企业产品体验。',
  'updated_at': '2026-08-17T15:30:00+08:00',
};

void main() {
  late MockEmployeeApiClient apiClient;
  late NetworkEmployeeRepository repository;

  setUp(() {
    apiClient = MockEmployeeApiClient();
    repository = NetworkEmployeeRepository(apiClient);
  });

  test(
    'fetches a complete filtered page and parses directory fields',
    () async {
      when(
        () => apiClient.getMap(
          ApiEndpoints.employees,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => {
          'count': 1,
          'next': null,
          'previous': null,
          'results': [employeeJson],
        },
      );

      final page = await repository.fetchEmployees(
        search: '林知',
        departmentId: '00000000-0000-0000-0000-000000000301',
        status: 'active',
        page: 2,
        pageSize: 20,
        ordering: '-full_name',
      );

      expect(page.count, 1);
      expect(page.results.single.employeeNo, 'EMP-0001');
      expect(page.results.single.department.name, '研发中心');
      expect(page.results.single.position?.name, '软件工程师');
      expect(page.results.single.hireDate, DateTime(2023, 5, 8));
      verify(
        () => apiClient.getMap(
          ApiEndpoints.employees,
          queryParameters: {
            'search': '林知',
            'department': '00000000-0000-0000-0000-000000000301',
            'status': 'active',
            'page': 2,
            'page_size': 20,
            'ordering': '-full_name',
          },
        ),
      ).called(1);
    },
  );

  test('omits empty optional filters from the request', () async {
    when(
      () => apiClient.getMap(
        ApiEndpoints.employees,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => {
        'count': 0,
        'next': null,
        'previous': null,
        'results': <dynamic>[],
      },
    );

    await repository.fetchEmployees(page: 1, pageSize: 20);

    verify(
      () => apiClient.getMap(
        ApiEndpoints.employees,
        queryParameters: {
          'page': 1,
          'page_size': 20,
          'ordering': 'employee_no',
        },
      ),
    ).called(1);
  });

  test('fetches employee detail by path id', () async {
    when(
      () => apiClient.getMap('${ApiEndpoints.employees}${employeeJson['id']}/'),
    ).thenAnswer((_) async => employeeJson);

    final employee = await repository.fetchEmployee(
      employeeJson['id']! as String,
    );

    expect(employee.fullName, '林知远');
    expect(employee.workEmail, 'lin.zhiyuan@example.test');
    expect(employee.avatarUrl, 'https://assets.example.test/avatar.png');
    expect(employee.gender, 'female');
    expect(employee.birthday, DateTime(1992, 6, 8));
    expect(employee.officeLocation, '上海 A 座 8F');
    expect(employee.manager?.fullName, '直属负责人');
    expect(employee.description, '负责企业产品体验。');
  });

  test('maps malformed employee data into a safe data failure', () async {
    when(
      () => apiClient.getMap(
        ApiEndpoints.employees,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => {
        'count': 1,
        'next': null,
        'previous': null,
        'results': [
          {'employee_no': 'EMP-0001'},
        ],
      },
    );

    await expectLater(
      repository.fetchEmployees(page: 1, pageSize: 20),
      throwsA(
        isA<Failure>().having((error) => error.type, 'type', FailureType.data),
      ),
    );
  });

  test('creates, patches, and performs employee status actions', () async {
    final input = <String, dynamic>{
      'employee_no': 'EMP-0001',
      'full_name': '林知远',
      'department': '00000000-0000-0000-0000-000000000301',
    };
    when(
      () => apiClient.postMap(ApiEndpoints.employees, data: input),
    ).thenAnswer((_) async => employeeJson);
    when(
      () => apiClient.patchMap(
        '${ApiEndpoints.employees}${employeeJson['id']}/',
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => {...employeeJson, 'full_name': '林知远（更新）'});
    when(
      () => apiClient.postMap(
        '${ApiEndpoints.employees}${employeeJson['id']}/depart/',
        data: const {},
      ),
    ).thenAnswer(
      (_) async => {
        'employee': {...employeeJson, 'employment_status': 'departed'},
        'changed': true,
      },
    );

    final created = await repository.createEmployee(input);
    final updated = await repository.updateEmployee(created.id, {
      'full_name': '林知远（更新）',
      'expected_updated_at': created.updatedAt!.toIso8601String(),
    });
    final departed = await repository.departEmployee(created.id);

    expect(updated.fullName, '林知远（更新）');
    expect(departed.changed, isTrue);
    expect(departed.employee.isActive, isFalse);
  });

  test('maps stale object conflict to a reload-safe failure', () async {
    when(
      () => apiClient.patchMap(
        '${ApiEndpoints.employees}${employeeJson['id']}/',
        data: any(named: 'data'),
      ),
    ).thenThrow(const AppException.conflict('stale_object'));

    await expectLater(
      repository.updateEmployee(employeeJson['id']! as String, {
        'full_name': '冲突更新',
      }),
      throwsA(
        isA<Failure>()
            .having((failure) => failure.type, 'type', FailureType.conflict)
            .having((failure) => failure.message, 'message', contains('重新加载')),
      ),
    );
  });
}
