import 'dart:typed_data';

import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/features/audit/data/audit_export_repository.dart';
import 'package:employee_app/features/audit/platform/audit_export_saver.dart';
import 'package:employee_app/features/audit/presentation/audit_export_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeExportRepository implements AuditExportRepository {
  AuditExportFilters? receivedFilters;

  @override
  Future<ApiDownload> export(AuditExportFilters filters) async {
    receivedFilters = filters;
    return ApiDownload(
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: 'audit-events-safe.csv',
    );
  }
}

class FakeExportSaver implements AuditExportSaver {
  Uint8List? receivedBytes;
  String? receivedFilename;
  AuditSaveResult result = const AuditSaveResult.saved('memory://audit.csv');

  @override
  Future<AuditSaveResult> save(Uint8List bytes, String filename) async {
    receivedBytes = bytes;
    receivedFilename = filename;
    return result;
  }
}

void main() {
  test(
    'exports bytes through the saver without retaining CSV in state',
    () async {
      final repository = FakeExportRepository();
      final saver = FakeExportSaver();
      final controller = AuditExportController(repository, saver);
      const filters = AuditExportFilters(action: 'update');

      final result = await controller.export(filters);

      expect(result.path, 'memory://audit.csv');
      expect(repository.receivedFilters, filters);
      expect(saver.receivedBytes, [1, 2, 3]);
      expect(saver.receivedFilename, 'audit-events-safe.csv');
      expect(controller.isExporting, isFalse);
    },
  );

  test(
    'returns a cancelled saver result without treating it as an error',
    () async {
      final repository = FakeExportRepository();
      final saver = FakeExportSaver()
        ..result = const AuditSaveResult.cancelled();
      final controller = AuditExportController(repository, saver);

      final result = await controller.export(const AuditExportFilters());

      expect(result.cancelled, isTrue);
      expect(controller.isExporting, isFalse);
    },
  );
}
