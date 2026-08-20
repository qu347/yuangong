import 'dart:typed_data';

import 'package:employee_app/core/errors/app_exception.dart';
import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/core/network/api_endpoints.dart';
import 'package:employee_app/features/audit/data/audit_export_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuditExportApiClient extends Mock implements ApiClient {}

void main() {
  test(
    'downloads audit CSV with the selected filters and safe filename',
    () async {
      final apiClient = MockAuditExportApiClient();
      final repository = NetworkAuditExportRepository(apiClient);
      when(
        () => apiClient.downloadBytes(
          ApiEndpoints.auditExport,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => ApiDownload(
          bytes: Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x61]),
          filename: 'audit-events-20260819T120000Z.csv',
        ),
      );
      const filters = AuditExportFilters(
        action: 'update',
        resourceType: 'employee',
      );

      final result = await repository.export(filters);

      expect(result.filename, 'audit-events-20260819T120000Z.csv');
      expect(result.bytes, [0xEF, 0xBB, 0xBF, 0x61]);
      verify(
        () => apiClient.downloadBytes(
          ApiEndpoints.auditExport,
          queryParameters: {
            'action': 'update',
            'resource_type': 'employee',
            'ordering': '-created_at',
          },
        ),
      ).called(1);
    },
  );

  test('maps server export limit to a safe actionable failure', () async {
    final apiClient = MockAuditExportApiClient();
    final repository = NetworkAuditExportRepository(apiClient);
    when(
      () => apiClient.downloadBytes(
        ApiEndpoints.auditExport,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenThrow(const AppException.validation('export_too_large'));

    await expectLater(
      repository.export(const AuditExportFilters()),
      throwsA(
        isA<Failure>().having(
          (failure) => failure.message,
          'message',
          '审计记录超过导出上限，请缩小筛选范围后重试。',
        ),
      ),
    );
  });
}
