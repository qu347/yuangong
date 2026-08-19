import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/audit_export_repository.dart';
import '../platform/audit_export_saver.dart';

final auditExportControllerProvider = Provider<AuditExportController>(
  (ref) => AuditExportController(
    ref.watch(auditExportRepositoryProvider),
    ref.watch(auditExportSaverProvider),
  ),
);

class AuditExportController {
  AuditExportController(this._repository, this._saver);

  final AuditExportRepository _repository;
  final AuditExportSaver _saver;
  bool isExporting = false;

  Future<AuditSaveResult> export(AuditExportFilters filters) async {
    if (isExporting) {
      throw StateError('audit export already in progress');
    }
    isExporting = true;
    try {
      final download = await _repository.export(filters);
      return await _saver.save(download.bytes, download.filename);
    } finally {
      isExporting = false;
    }
  }
}
