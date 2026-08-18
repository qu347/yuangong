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

abstract class EmployeeRepository {
  Future<EmployeePage> fetchEmployees({
    String search = '',
    String? departmentId,
    String? status,
    int page = 1,
    int pageSize = 20,
    String ordering = 'employee_no',
  });

  Future<Employee> fetchEmployee(String id);
  Future<Employee> createEmployee(Map<String, dynamic> data) =>
      throw UnimplementedError();
  Future<Employee> updateEmployee(String id, Map<String, dynamic> data) =>
      throw UnimplementedError();
  Future<EmployeeActionResult> departEmployee(String id) =>
      throw UnimplementedError();
  Future<EmployeeActionResult> reactivateEmployee(String id) =>
      throw UnimplementedError();
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

  @override
  Future<Employee> createEmployee(Map<String, dynamic> data) => _writeEmployee(
    () => _apiClient.postMap(ApiEndpoints.employees, data: data),
  );

  @override
  Future<Employee> updateEmployee(String id, Map<String, dynamic> data) =>
      _writeEmployee(
        () => _apiClient.patchMap('${ApiEndpoints.employees}$id/', data: data),
      );

  @override
  Future<EmployeeActionResult> departEmployee(String id) =>
      _employeeAction('${ApiEndpoints.employees}$id/depart/');

  @override
  Future<EmployeeActionResult> reactivateEmployee(String id) =>
      _employeeAction('${ApiEndpoints.employees}$id/reactivate/');

  Future<Employee> _writeEmployee(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    try {
      return Employee.fromJson(await request());
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  Future<EmployeeActionResult> _employeeAction(String path) async {
    try {
      return EmployeeActionResult.fromJson(
        await _apiClient.postMap(path, data: const {}),
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
      AppExceptionType.conflict when error.message == 'stale_object' =>
        const Failure.conflict('员工信息已被其他操作更新，请重新加载后再试。'),
      AppExceptionType.conflict => const Failure.conflict(),
      AppExceptionType.protocol => const Failure.service(),
      AppExceptionType.unexpected => const Failure(
        type: FailureType.unexpected,
        message: '加载员工目录失败，请稍后重试。',
      ),
    };
  }
}
