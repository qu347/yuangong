import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'audit_event.dart';

final auditRepositoryProvider = Provider<AuditRepository>(
  (ref) => NetworkAuditRepository(ref.watch(apiClientProvider)),
);

abstract interface class AuditRepository {
  Future<AuditEventPage> fetchAuditEvents({
    String? action,
    String? resourceType,
    int page = 1,
    int pageSize = 20,
  });
}

class NetworkAuditRepository implements AuditRepository {
  const NetworkAuditRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<AuditEventPage> fetchAuditEvents({
    String? action,
    String? resourceType,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      return AuditEventPage.fromJson(
        await _apiClient.getMap(
          ApiEndpoints.auditEvents,
          queryParameters: {
            if (action != null && action.isNotEmpty) 'action': action,
            if (resourceType != null && resourceType.isNotEmpty)
              'resource_type': resourceType,
            'page': page,
            'page_size': pageSize,
            'ordering': '-created_at',
          },
        ),
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
          message: '加载审计事件失败，请稍后重试。',
        ),
      };
    } on FormatException {
      throw const Failure.data();
    }
  }
}
