import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'employee.dart';
import 'employee_page.dart';

final employeeRepositoryProvider = Provider<EmployeeRepository>(
  (ref) => NetworkEmployeeRepository(ref.watch(apiClientProvider)),
);

abstract interface class EmployeeRepository {
  Future<EmployeePage> fetchEmployees({
    String search = '',
    String? departmentId,
    String? status,
    int page = 1,
    int pageSize = 20,
    String ordering = 'employee_no',
  });

  Future<Employee> fetchEmployee(String id);
}

class NetworkEmployeeRepository implements EmployeeRepository {
  const NetworkEmployeeRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<EmployeePage> fetchEmployees({
    String search = '',
    String? departmentId,
    String? status,
    int page = 1,
    int pageSize = 20,
    String ordering = 'employee_no',
  }) async {
    final query = <String, dynamic>{
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (departmentId != null && departmentId.isNotEmpty)
        'department': departmentId,
      if (status != null && status.isNotEmpty) 'status': status,
      'page': page,
      'page_size': pageSize,
      'ordering': ordering,
    };
    try {
      return EmployeePage.fromJson(
        await _apiClient.getMap(ApiEndpoints.employees, queryParameters: query),
      );
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  @override
  Future<Employee> fetchEmployee(String id) async {
    try {
      return Employee.fromJson(
        await _apiClient.getMap('${ApiEndpoints.employees}$id/'),
      );
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  Failure _failureFor(AppException error) {
    return switch (error.type) {
      AppExceptionType.network => const Failure.network(),
      AppExceptionType.unauthorized => const Failure.authentication(),
      AppExceptionType.forbidden => const Failure.permission(),
      AppExceptionType.validation => const Failure.validation(),
      AppExceptionType.protocol => const Failure.service(),
      AppExceptionType.unexpected => const Failure(
        type: FailureType.unexpected,
        message: '加载员工目录失败，请稍后重试。',
      ),
    };
  }
}
