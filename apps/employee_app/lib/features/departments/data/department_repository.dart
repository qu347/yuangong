import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'department.dart';

final departmentRepositoryProvider = Provider<DepartmentRepository>(
  (ref) => NetworkDepartmentRepository(ref.watch(apiClientProvider)),
);

abstract interface class DepartmentRepository {
  Future<List<Department>> fetchDepartments();
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
}
