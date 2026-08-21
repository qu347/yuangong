import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/files/safe_filename.dart';
import '../data/attachment_repository.dart';
import 'attachment_android_document_saver.dart';

final attachmentFileSaverProvider = Provider<AttachmentFileSaver>(
  (ref) => FileSelectorAttachmentFileSaver(),
);

class AttachmentSaveResult {
  const AttachmentSaveResult.saved(this.location) : cancelled = false;
  const AttachmentSaveResult.cancelled() : cancelled = true, location = null;

  final bool cancelled;
  final String? location;

  String? get path => location;
}

abstract interface class AttachmentFileSaver {
  Future<AttachmentSaveResult> save(
    Uint8List bytes,
    String filename,
    String mimeType,
  );
}

enum AttachmentSavePlatform { windows, android, unsupported }

typedef AttachmentChooseSavePath =
    Future<String?> Function(
      String filename,
      List<XTypeGroup> acceptedTypeGroups,
    );
typedef AttachmentWriteFile =
    Future<void> Function(
      Uint8List bytes,
      String path,
      String mimeType,
      String filename,
    );

class FileSelectorAttachmentFileSaver implements AttachmentFileSaver {
  FileSelectorAttachmentFileSaver({
    AttachmentSavePlatform? platform,
    AttachmentChooseSavePath? chooseSavePath,
    AttachmentWriteFile? writeFile,
    AndroidAttachmentDocumentSaver? androidDocumentSaver,
  }) : _platform = platform,
       _chooseSavePath = chooseSavePath ?? _defaultChooseSavePath,
       _writeFile = writeFile ?? _defaultWriteFile,
       _androidDocumentSaver =
           androidDocumentSaver ??
           MethodChannelAndroidAttachmentDocumentSaver();

  final AttachmentSavePlatform? _platform;
  final AttachmentChooseSavePath _chooseSavePath;
  final AttachmentWriteFile _writeFile;
  final AndroidAttachmentDocumentSaver _androidDocumentSaver;

  @override
  Future<AttachmentSaveResult> save(
    Uint8List bytes,
    String filename,
    String mimeType,
  ) async {
    try {
      return await _save(bytes, filename, mimeType);
    } on Failure {
      rethrow;
    } on Object {
      throw const Failure(
        type: FailureType.unexpected,
        message: '附件保存失败，请稍后重试。',
      );
    }
  }

  Future<AttachmentSaveResult> _save(
    Uint8List bytes,
    String filename,
    String mimeType,
  ) async {
    final extension = _safeExtension(filename);
    final expectedMimeType = _mimeTypeForExtension(extension);
    if (expectedMimeType == null ||
        mimeType.toLowerCase() != expectedMimeType) {
      throw const Failure.data();
    }
    final typeGroup = XTypeGroup(
      label: extension.toUpperCase(),
      extensions: [extension],
    );
    final platform = _platform ?? _currentPlatform();
    final String? location;
    switch (platform) {
      case AttachmentSavePlatform.windows:
        final targetPath = await _chooseSavePath(filename, [typeGroup]);
        if (targetPath == null) {
          return const AttachmentSaveResult.cancelled();
        }
        await _writeFile(bytes, targetPath, mimeType, filename);
        location = targetPath;
      case AttachmentSavePlatform.android:
        try {
          location = await _androidDocumentSaver.save(
            bytes,
            filename,
            mimeType,
          );
        } on PlatformException catch (error) {
          if (error.code == 'attachment_save_in_progress') {
            throw const Failure.conflict('已有附件正在保存。');
          }
          throw const Failure(
            type: FailureType.unexpected,
            message: '附件保存失败，请稍后重试。',
          );
        } on MissingPluginException {
          throw const Failure(
            type: FailureType.unexpected,
            message: '当前平台不支持保存附件。',
          );
        }
      case AttachmentSavePlatform.unsupported:
        throw const Failure(
          type: FailureType.unexpected,
          message: '当前平台不支持保存附件。',
        );
    }
    if (location == null) {
      return const AttachmentSaveResult.cancelled();
    }
    return AttachmentSaveResult.saved(location);
  }

  static Future<String?> _defaultChooseSavePath(
    String filename,
    List<XTypeGroup> acceptedTypeGroups,
  ) async {
    final location = await getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: acceptedTypeGroups,
    );
    return location?.path;
  }

  static Future<void> _defaultWriteFile(
    Uint8List bytes,
    String path,
    String mimeType,
    String filename,
  ) => XFile.fromData(bytes, mimeType: mimeType, name: filename).saveTo(path);
}

AttachmentSavePlatform _currentPlatform() {
  if (Platform.isWindows) {
    return AttachmentSavePlatform.windows;
  }
  if (Platform.isAndroid) {
    return AttachmentSavePlatform.android;
  }
  return AttachmentSavePlatform.unsupported;
}

String _safeExtension(String filename) {
  final extension = SafeFilenamePolicy.extensionOf(filename);
  if (extension == null ||
      !SafeFilenamePolicy.isSafe(
        filename,
        allowedExtensions: attachmentAllowedExtensions,
      )) {
    throw const Failure.data();
  }
  return extension;
}

String? _mimeTypeForExtension(String extension) => switch (extension) {
  'pdf' => 'application/pdf',
  'docx' =>
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'jpg' || 'jpeg' => 'image/jpeg',
  'png' => 'image/png',
  _ => null,
};
