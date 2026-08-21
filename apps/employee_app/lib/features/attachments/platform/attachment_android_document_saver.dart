import 'package:flutter/services.dart';

abstract interface class AndroidAttachmentDocumentSaver {
  static const channelName =
      'com.yourcompany.employee_app/attachment_document_saver';

  Future<String?> save(Uint8List bytes, String filename, String mimeType);
}

class MethodChannelAndroidAttachmentDocumentSaver
    implements AndroidAttachmentDocumentSaver {
  MethodChannelAndroidAttachmentDocumentSaver({
    this.channel = const MethodChannel(
      AndroidAttachmentDocumentSaver.channelName,
    ),
  });

  final MethodChannel channel;
  bool _saving = false;

  @override
  Future<String?> save(
    Uint8List bytes,
    String filename,
    String mimeType,
  ) async {
    if (_saving) {
      throw PlatformException(
        code: 'attachment_save_in_progress',
        message: '已有附件正在保存。',
      );
    }
    _saving = true;
    try {
      return await channel.invokeMethod<String>('saveAttachment', {
        'bytes': bytes,
        'filename': filename,
        'mimeType': mimeType,
      });
    } finally {
      _saving = false;
    }
  }
}
