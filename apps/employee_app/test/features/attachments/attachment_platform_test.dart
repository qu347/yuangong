import 'dart:async';
import 'dart:io';

import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/features/attachments/platform/attachment_android_document_saver.dart';
import 'package:employee_app/features/attachments/platform/attachment_file_picker.dart';
import 'package:employee_app/features/attachments/platform/attachment_file_saver.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('picker returns null when selection is cancelled', () async {
    final picker = FileSelectorAttachmentFilePicker(
      openFile: (_) async => null,
    );

    expect(await picker.pick(), isNull);
  });

  test('picker derives a normalized supported candidate', () async {
    List<XTypeGroup>? receivedGroups;
    final picker = FileSelectorAttachmentFilePicker(
      openFile: (groups) async {
        receivedGroups = groups;
        return XFile.fromData(
          Uint8List.fromList([1, 2, 3]),
          path: r'C:\temp\合同.PDF',
        );
      },
    );

    final candidate = await picker.pick();

    expect(candidate?.name, '合同.PDF');
    expect(candidate?.extension, 'pdf');
    expect(candidate?.size, 3);
    expect(
      receivedGroups!.expand((group) => group.extensions ?? const <String>[]),
      containsAll(['pdf', 'docx', 'xlsx', 'jpg', 'jpeg', 'png']),
    );
  });

  test('picker rejects unsupported, empty, and oversized files', () async {
    Future<void> expectRejected(String path, int length, String message) async {
      final picker = FileSelectorAttachmentFilePicker(
        openFile: (_) async =>
            XFile.fromData(Uint8List(0), path: path, length: length),
      );
      await expectLater(
        picker.pick(),
        throwsA(
          isA<Failure>().having(
            (failure) => failure.message,
            'message',
            message,
          ),
        ),
      );
    }

    await expectRejected(
      r'C:\temp\malware.exe',
      10,
      '不支持该附件类型，请选择 PDF、DOCX、XLSX、JPG、JPEG 或 PNG 文件。',
    );
    await expectRejected(r'C:\temp\empty.pdf', 0, '附件内容不能为空。');
    await expectRejected(
      r'C:\temp\large.pdf',
      10 * 1024 * 1024 + 1,
      '附件大小不能超过 10 MiB。',
    );
  });

  test('picker and saver reject the same Unicode format controls', () async {
    final unsafeNames = [
      'unsafe\u00AD.pdf',
      'unsafe\u061C.pdf',
      'unsafe\u180E.pdf',
      'unsafe\u{E0001}.pdf',
    ];

    for (final filename in unsafeNames) {
      final picker = FileSelectorAttachmentFilePicker(
        openFile: (_) async => XFile.fromData(
          Uint8List.fromList([1]),
          path: 'C:\\temp\\$filename',
        ),
      );
      await expectLater(
        picker.pick(),
        throwsA(isA<Failure>()),
        reason: 'picker accepted $filename',
      );

      var saveDialogOpened = false;
      final saver = FileSelectorAttachmentFileSaver(
        platform: AttachmentSavePlatform.windows,
        chooseSavePath: (_, _) async {
          saveDialogOpened = true;
          return null;
        },
      );
      await expectLater(
        saver.save(Uint8List.fromList([1]), filename, 'application/pdf'),
        throwsA(isA<Failure>()),
        reason: 'saver accepted $filename',
      );
      expect(saveDialogOpened, isFalse);
    }
  });

  test('Windows saver cancellation is a non-error result', () async {
    final saver = FileSelectorAttachmentFileSaver(
      platform: AttachmentSavePlatform.windows,
      chooseSavePath: (_, _) async => null,
    );

    final result = await saver.save(
      Uint8List.fromList([1]),
      'contract.pdf',
      'application/pdf',
    );

    expect(result.cancelled, isTrue);
    expect(result.path, isNull);
  });

  test('Windows write exceptions map to a safe Chinese failure', () async {
    final saver = FileSelectorAttachmentFileSaver(
      platform: AttachmentSavePlatform.windows,
      chooseSavePath: (_, _) async => r'C:\downloads\contract.pdf',
      writeFile: (_, _, _, _) async {
        throw const FileSystemException('sensitive operating system detail');
      },
    );

    await expectLater(
      saver.save(Uint8List.fromList([1]), 'contract.pdf', 'application/pdf'),
      throwsA(
        isA<Failure>().having(
          (failure) => failure.message,
          'message',
          '附件保存失败，请稍后重试。',
        ),
      ),
    );
  });

  test(
    'Android document saver sends bytes and returns a content URI',
    () async {
      const channel = MethodChannel(AndroidAttachmentDocumentSaver.channelName);
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            receivedCall = call;
            return 'content://downloads/document/42';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final saver = FileSelectorAttachmentFileSaver(
        platform: AttachmentSavePlatform.android,
        androidDocumentSaver: MethodChannelAndroidAttachmentDocumentSaver(
          channel: channel,
        ),
      );

      final result = await saver.save(
        Uint8List.fromList([1, 2]),
        '合同.pdf',
        'application/pdf',
      );

      expect(receivedCall?.method, 'saveAttachment');
      final arguments = receivedCall?.arguments as Map<Object?, Object?>;
      expect(arguments['filename'], '合同.pdf');
      expect(arguments['mimeType'], 'application/pdf');
      expect(arguments['bytes'], Uint8List.fromList([1, 2]));
      expect(result.location, 'content://downloads/document/42');
      expect(result.cancelled, isFalse);
    },
  );

  test('Android document saver cancellation is a non-error result', () async {
    const channel = MethodChannel(AndroidAttachmentDocumentSaver.channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final saver = FileSelectorAttachmentFileSaver(
      platform: AttachmentSavePlatform.android,
      androidDocumentSaver: MethodChannelAndroidAttachmentDocumentSaver(
        channel: channel,
      ),
    );

    final result = await saver.save(
      Uint8List.fromList([1]),
      '合同.pdf',
      'application/pdf',
    );

    expect(result.cancelled, isTrue);
    expect(result.location, isNull);
  });

  test('Android provider failures map to a safe Chinese failure', () async {
    const channel = MethodChannel(AndroidAttachmentDocumentSaver.channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(
            code: 'attachment_save_failed',
            message: 'provider detail must not escape',
          ),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final saver = FileSelectorAttachmentFileSaver(
      platform: AttachmentSavePlatform.android,
      androidDocumentSaver: MethodChannelAndroidAttachmentDocumentSaver(
        channel: channel,
      ),
    );

    await expectLater(
      saver.save(Uint8List.fromList([1]), '合同.pdf', 'application/pdf'),
      throwsA(
        isA<Failure>().having(
          (failure) => failure.message,
          'message',
          '附件保存失败，请稍后重试。',
        ),
      ),
    );
  });

  test(
    'Android saver rejects a second call while pending and releases once',
    () async {
      const channel = MethodChannel(AndroidAttachmentDocumentSaver.channelName);
      final firstCompletion = Completer<String?>();
      var nativeCallCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            nativeCallCount += 1;
            if (nativeCallCount == 1) {
              return firstCompletion.future;
            }
            return 'content://downloads/document/second';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final saver = FileSelectorAttachmentFileSaver(
        platform: AttachmentSavePlatform.android,
        androidDocumentSaver: MethodChannelAndroidAttachmentDocumentSaver(
          channel: channel,
        ),
      );

      final firstSave = saver.save(
        Uint8List.fromList([1]),
        'first.pdf',
        'application/pdf',
      );
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        saver.save(Uint8List.fromList([2]), 'second.pdf', 'application/pdf'),
        throwsA(
          isA<Failure>().having(
            (failure) => failure.message,
            'message',
            '已有附件正在保存。',
          ),
        ),
      );
      expect(nativeCallCount, 1);

      firstCompletion.complete('content://downloads/document/first');
      expect((await firstSave).location, 'content://downloads/document/first');
      expect(
        (await saver.save(
          Uint8List.fromList([3]),
          'third.pdf',
          'application/pdf',
        )).location,
        'content://downloads/document/second',
      );
      expect(nativeCallCount, 2);
    },
  );
}
