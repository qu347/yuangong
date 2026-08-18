import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'position.dart';

final positionRepositoryProvider = Provider<PositionRepository>(
  (ref) => NetworkPositionRepository(ref.watch(apiClientProvider)),
);

abstract interface class PositionRepository {
  Future<List<Position>> fetchPositions();
  Future<Position> createPosition(Map<String, dynamic> data);
  Future<Position> updatePosition(String id, Map<String, dynamic> data);
  Future<PositionActionResult> activatePosition(String id);
  Future<PositionActionResult> deactivatePosition(String id);
}

class NetworkPositionRepository implements PositionRepository {
  const NetworkPositionRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<Position>> fetchPositions() async {
    try {
      return List<Position>.unmodifiable(
        (await _apiClient.getList(ApiEndpoints.positions)).map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('invalid position item');
          }
          return Position.fromJson(item);
        }),
      );
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  @override
  Future<Position> createPosition(Map<String, dynamic> data) =>
      _write(() => _apiClient.postMap(ApiEndpoints.positions, data: data));

  @override
  Future<Position> updatePosition(String id, Map<String, dynamic> data) =>
      _write(
        () => _apiClient.patchMap('${ApiEndpoints.positions}$id/', data: data),
      );

  @override
  Future<PositionActionResult> activatePosition(String id) =>
      _action('${ApiEndpoints.positions}$id/activate/');

  @override
  Future<PositionActionResult> deactivatePosition(String id) =>
      _action('${ApiEndpoints.positions}$id/deactivate/');

  Future<Position> _write(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    try {
      return Position.fromJson(await request());
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  Future<PositionActionResult> _action(String path) async {
    try {
      return PositionActionResult.fromJson(
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
      AppExceptionType.conflict => const Failure.conflict('该岗位仍有在用依赖，无法执行此操作。'),
      AppExceptionType.protocol => const Failure.service(),
      AppExceptionType.unexpected => const Failure(
        type: FailureType.unexpected,
        message: '更新岗位目录失败，请稍后重试。',
      ),
    };
  }
}
