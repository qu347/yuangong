import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/files/safe_filename.dart';
import '../data/attachment.dart';
import '../data/attachment_repository.dart';

const attachmentMaxBytes = 10 * 1024 * 1024;

final attachmentFilePickerProvider = Provider<AttachmentFilePicker>(
  (ref) => FileSelectorAttachmentFilePicker(),
);

abstract interface class AttachmentFilePicker {
  Future<AttachmentUploadCandidate?> pick();
}

typedef AttachmentOpenFile =
    Future<XFile?> Function(List<XTypeGroup> acceptedTypeGroups);

class FileSelectorAttachmentFilePicker implements AttachmentFilePicker {
  FileSelectorAttachmentFilePicker({AttachmentOpenFile? openFile})
    : _openFile = openFile ?? _openAttachmentFile;

  static const _typeGroups = [
    XTypeGroup(
      label: '员工附件',
      extensions: ['pdf', 'docx', 'xlsx', 'jpg', 'jpeg', 'png'],
    ),
  ];

  final AttachmentOpenFile _openFile;

  static Future<XFile?> _openAttachmentFile(List<XTypeGroup> groups) =>
      openFile(acceptedTypeGroups: groups);

  @override
  Future<AttachmentUploadCandidate?> pick() async {
    final file = await _openFile(_typeGroups);
    if (file == null) {
      return null;
    }
    final filename = SafeFilenamePolicy.basename(file.path);
    final extension = SafeFilenamePolicy.extensionOf(filename) ?? '';
    if (!attachmentAllowedExtensions.contains(extension)) {
      throw const Failure.validation(
        '不支持该附件类型，请选择 PDF、DOCX、XLSX、JPG、JPEG 或 PNG 文件。',
      );
    }
    if (!SafeFilenamePolicy.isSafe(
      filename,
      allowedExtensions: attachmentAllowedExtensions,
    )) {
      throw const Failure.validation('附件文件名无效，请重新选择。');
    }
    final size = await file.length();
    if (size <= 0) {
      throw const Failure.validation('附件内容不能为空。');
    }
    if (size > attachmentMaxBytes) {
      throw const Failure.validation('附件大小不能超过 10 MiB。');
    }
    return AttachmentUploadCandidate(
      path: file.path,
      name: filename,
      size: size,
      extension: extension,
    );
  }
}
