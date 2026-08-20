import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

final auditExportRepositoryProvider = Provider<AuditExportRepository>(
  (ref) => NetworkAuditExportRepository(ref.watch(apiClientProvider)),
);

class AuditExportFilters {
  const AuditExportFilters({this.action, this.resourceType});

  final String? action;
  final String? resourceType;

  Map<String, dynamic> toQueryParameters() => {
    if (action != null && action!.isNotEmpty) 'action': action,
    if (resourceType != null && resourceType!.isNotEmpty)
      'resource_type': resourceType,
    'ordering': '-created_at',
  };

  String get summary {
    final parts = <String>[
      if (action != null && action!.isNotEmpty) '操作：$action',
      if (resourceType != null && resourceType!.isNotEmpty) '资源：$resourceType',
    ];
    return parts.isEmpty ? '全部审计记录' : parts.join('；');
  }

  @override
  bool operator ==(Object other) =>
      other is AuditExportFilters &&
      other.action == action &&
      other.resourceType == resourceType;

  @override
  int get hashCode => Object.hash(action, resourceType);
}

abstract interface class AuditExportRepository {
  Future<ApiDownload> export(AuditExportFilters filters);
}

class NetworkAuditExportRepository implements AuditExportRepository {
  const NetworkAuditExportRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ApiDownload> export(AuditExportFilters filters) async {
    try {
      return await _apiClient.downloadBytes(
        ApiEndpoints.auditExport,
        queryParameters: filters.toQueryParameters(),
      );
    } on AppException catch (error) {
      throw switch (error.type) {
        AppExceptionType.network => const Failure.network(),
        AppExceptionType.unauthorized => const Failure.authentication(),
        AppExceptionType.forbidden => const Failure.permission(),
        AppExceptionType.validation when error.message == 'export_too_large' =>
          const Failure.validation('审计记录超过导出上限，请缩小筛选范围后重试。'),
        AppExceptionType.validation => const Failure.validation(),
        AppExceptionType.conflict => const Failure.conflict(),
        AppExceptionType.protocol => const Failure.service(),
        AppExceptionType.unexpected => const Failure(
          type: FailureType.unexpected,
          message: '审计导出失败，请稍后重试。',
        ),
      };
    }
  }
}
