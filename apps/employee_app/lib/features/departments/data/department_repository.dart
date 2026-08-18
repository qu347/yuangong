import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'department.dart';

final departmentRepositoryProvider = Provider<DepartmentRepository>(
  (ref) => NetworkDepartmentRepository(ref.watch(apiClientProvider)),
);

abstract class DepartmentRepository {
  Future<List<Department>> fetchDepartments();
  Future<Department> createDepartment(Map<String, dynamic> data) =>
      throw UnimplementedError();
  Future<Department> updateDepartment(String id, Map<String, dynamic> data) =>
      throw UnimplementedError();
  Future<DepartmentActionResult> activateDepartment(String id) =>
      throw UnimplementedError();
  Future<DepartmentActionResult> deactivateDepartment(String id) =>
      throw UnimplementedError();
}

class NetworkDepartmentRepository implements DepartmentRepository {
  const NetworkDepartmentRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<Department>> fetchDepartments() async {
    try {
      return List<Department>.unmodifiable(
        (await _apiClient.getList(ApiEndpoints.departments)).map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('invalid department item');
          }
          return Department.fromJson(item);
        }),
      );
    } on AppException catch (error) {
      throw switch (error.type) {
        AppExceptionType.network => const Failure.network(),
        AppExceptionType.unauthorized => const Failure.authentication(),
        AppExceptionType.forbidden => const Failure.permission(),
        AppExceptionType.validation => const Failure.validation(),
        AppExceptionType.conflict => const Failure.conflict(),
        AppExceptionType.protocol => const Failure.service(),
        AppExceptionType.unexpected => const Failure(
          type: FailureType.unexpected,
          message: '加载部门目录失败，请稍后重试。',
        ),
      };
    } on FormatException {
      throw const Failure.data();
    }
  }

  @override
  Future<Department> createDepartment(Map<String, dynamic> data) =>
      _writeDepartment(
        () => _apiClient.postMap(ApiEndpoints.departments, data: data),
      );

  @override
  Future<Department> updateDepartment(String id, Map<String, dynamic> data) =>
      _writeDepartment(
        () =>
            _apiClient.patchMap('${ApiEndpoints.departments}$id/', data: data),
      );

  @override
  Future<DepartmentActionResult> activateDepartment(String id) =>
      _departmentAction('${ApiEndpoints.departments}$id/activate/');

  @override
  Future<DepartmentActionResult> deactivateDepartment(String id) =>
      _departmentAction('${ApiEndpoints.departments}$id/deactivate/');

  Future<Department> _writeDepartment(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    try {
      return Department.fromJson(await request());
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  Future<DepartmentActionResult> _departmentAction(String path) async {
    try {
      return DepartmentActionResult.fromJson(
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
      AppExceptionType.conflict => const Failure.conflict(
        '该目录仍有在用依赖，无法变更状态或归属。',
      ),
      AppExceptionType.protocol => const Failure.service(),
      AppExceptionType.unexpected => const Failure(
        type: FailureType.unexpected,
        message: '更新部门目录失败，请稍后重试。',
      ),
    };
  }
}
