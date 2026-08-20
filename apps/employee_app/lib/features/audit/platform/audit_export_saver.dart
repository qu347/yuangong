import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';

final auditExportSaverProvider = Provider<AuditExportSaver>(
  (ref) => const FileSelectorAuditExportSaver(),
);

class AuditSaveResult {
  const AuditSaveResult.saved(this.path) : cancelled = false;
  const AuditSaveResult.cancelled() : cancelled = true, path = null;

  final bool cancelled;
  final String? path;
}

abstract interface class AuditExportSaver {
  Future<AuditSaveResult> save(Uint8List bytes, String filename);
}

class FileSelectorAuditExportSaver implements AuditExportSaver {
  const FileSelectorAuditExportSaver();

  @override
  Future<AuditSaveResult> save(Uint8List bytes, String filename) async {
    if (!RegExp(r'^[A-Za-z0-9._-]+[.]csv$').hasMatch(filename)) {
      throw const Failure.data();
    }
    String? targetPath;
    if (Platform.isWindows) {
      const csvType = XTypeGroup(label: 'CSV', extensions: ['csv']);
      final location = await getSaveLocation(
        suggestedName: filename,
        acceptedTypeGroups: const [csvType],
      );
      targetPath = location?.path;
    } else if (Platform.isAndroid) {
      final directory = await getDirectoryPath(confirmButtonText: '选择保存目录');
      if (directory != null) {
        targetPath = '$directory${Platform.pathSeparator}$filename';
      }
    } else {
      throw const Failure(
        type: FailureType.unexpected,
        message: '当前平台不支持审计导出保存。',
      );
    }
    if (targetPath == null) {
      return const AuditSaveResult.cancelled();
    }
    final file = XFile.fromData(bytes, mimeType: 'text/csv', name: filename);
    await file.saveTo(targetPath);
    return AuditSaveResult.saved(targetPath);
  }
}
