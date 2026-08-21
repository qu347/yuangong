import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:employee_app/core/errors/app_exception.dart';
import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/core/network/api_endpoints.dart';
import 'package:employee_app/features/attachments/data/attachment.dart';
import 'package:employee_app/features/attachments/data/attachment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockApiClient extends Mock implements ApiClient {}

const _attachmentJson = <String, dynamic>{
  'id': '10000000-0000-0000-0000-000000000001',
  'employee_id': '20000000-0000-0000-0000-000000000001',
  'filename': '合同.pdf',
  'file_type': 'pdf',
  'file_size': 1024,
  'uploaded_by': {
    'id': '30000000-0000-0000-0000-000000000001',
    'username': 'hr.manager',
  },
  'created_at': '2026-08-21T09:30:00Z',
};

void main() {
  setUpAll(() {
    registerFallbackValue(FormData());
  });

  test('fetches and parses the nested paginated attachment list', () async {
    final apiClient = _MockApiClient();
    final repository = NetworkAttachmentRepository(apiClient);
    when(
      () => apiClient.getMap(
        ApiEndpoints.employeeAttachments('employee-id'),
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => {
        'count': 1,
        'next': null,
        'previous': null,
        'results': [_attachmentJson],
      },
    );

    final page = await repository.fetchAttachments(
      'employee-id',
      page: 2,
      pageSize: 10,
    );

    expect(page.count, 1);
    expect(page.results.single.filename, '合同.pdf');
    expect(page.results.single.uploadedBy?.username, 'hr.manager');
    verify(
      () => apiClient.getMap(
        ApiEndpoints.employeeAttachments('employee-id'),
        queryParameters: {'page': 2, 'page_size': 10},
      ),
    ).called(1);
  });

  test(
    'upload sends one real multipart file and parses safe metadata',
    () async {
      final apiClient = _MockApiClient();
      final repository = NetworkAttachmentRepository(apiClient);
      final directory = await Directory.systemTemp.createTemp(
        'employee-attachment-repository-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(
        '${directory.path}${Platform.pathSeparator}contract.pdf',
      );
      await file.writeAsBytes(List<int>.filled(1024, 1));
      when(
        () => apiClient.postMap(
          ApiEndpoints.employeeAttachments('employee-id'),
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => _attachmentJson);

      final attachment = await repository.uploadAttachment(
        'employee-id',
        AttachmentUploadCandidate(
          path: file.path,
          name: 'contract.pdf',
          size: 1024,
          extension: 'pdf',
        ),
      );

      expect(attachment.filename, '合同.pdf');
      expect(attachment.fileSize, 1024);
      final captured =
          verify(
                () => apiClient.postMap(
                  ApiEndpoints.employeeAttachments('employee-id'),
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as FormData;
      expect(captured.fields, isEmpty);
      expect(captured.files, hasLength(1));
      expect(captured.files.single.key, 'file');
      expect(captured.files.single.value.filename, 'contract.pdf');
      expect(captured.files.single.value.length, 1024);
    },
  );

  test('download and delete use the global attachment endpoints', () async {
    final apiClient = _MockApiClient();
    final repository = NetworkAttachmentRepository(apiClient);
    final expected = ApiFileDownload(
      bytes: Uint8List.fromList([1, 2]),
      filename: 'contract.pdf',
      mimeType: 'application/pdf',
    );
    when(
      () => apiClient.downloadFile(
        ApiEndpoints.attachmentDownload('attachment-id'),
        fallbackFilename: 'attachment.pdf',
        allowedExtensions: any(named: 'allowedExtensions'),
      ),
    ).thenAnswer((_) async => expected);
    when(
      () => apiClient.deleteVoid(ApiEndpoints.attachment('attachment-id')),
    ).thenAnswer((_) async {});

    final download = await repository.downloadAttachment(
      'attachment-id',
      fileType: 'pdf',
    );
    await repository.deleteAttachment('attachment-id');

    expect(download, same(expected));
    verify(
      () => apiClient.downloadFile(
        ApiEndpoints.attachmentDownload('attachment-id'),
        fallbackFilename: 'attachment.pdf',
        allowedExtensions: const {'pdf', 'docx', 'xlsx', 'jpg', 'jpeg', 'png'},
      ),
    ).called(1);
    verify(
      () => apiClient.deleteVoid(ApiEndpoints.attachment('attachment-id')),
    ).called(1);
  });

  test(
    'download chooses a canonical fallback for each attachment type',
    () async {
      const expectedFallbacks = {
        'pdf': 'attachment.pdf',
        'docx': 'attachment.docx',
        'xlsx': 'attachment.xlsx',
        'jpg': 'attachment.jpg',
        'png': 'attachment.png',
      };

      for (final entry in expectedFallbacks.entries) {
        final apiClient = _MockApiClient();
        final repository = NetworkAttachmentRepository(apiClient);
        when(
          () => apiClient.downloadFile(
            ApiEndpoints.attachmentDownload('attachment-id'),
            fallbackFilename: entry.value,
            allowedExtensions: any(named: 'allowedExtensions'),
          ),
        ).thenAnswer(
          (_) async => ApiFileDownload(
            bytes: Uint8List.fromList([1]),
            filename: entry.value,
            mimeType: 'unused',
          ),
        );

        final download = await repository.downloadAttachment(
          'attachment-id',
          fileType: entry.key,
        );

        expect(download.filename, entry.value);
        verify(
          () => apiClient.downloadFile(
            ApiEndpoints.attachmentDownload('attachment-id'),
            fallbackFilename: entry.value,
            allowedExtensions: attachmentAllowedExtensions,
          ),
        ).called(1);
      }
    },
  );

  test('maps stable attachment upload errors to Simplified Chinese', () async {
    final apiClient = _MockApiClient();
    final repository = NetworkAttachmentRepository(apiClient);
    final directory = await Directory.systemTemp.createTemp(
      'employee-attachment-error-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}large.pdf');
    await file.writeAsBytes([1]);
    when(
      () => apiClient.postMap(any(), data: any(named: 'data')),
    ).thenThrow(const AppException.validation('attachment_too_large'));

    await expectLater(
      repository.uploadAttachment(
        'employee-id',
        AttachmentUploadCandidate(
          path: file.path,
          name: 'unused.pdf',
          size: 11 * 1024 * 1024,
          extension: 'pdf',
        ),
      ),
      throwsA(
        isA<Failure>().having(
          (failure) => failure.message,
          'message',
          '附件大小不能超过 10 MiB。',
        ),
      ),
    );
  });

  test(
    'maps HTTP 400 storage collision to the retry-specific failure',
    () async {
      final apiClient = _MockApiClient();
      final repository = NetworkAttachmentRepository(apiClient);
      final directory = await Directory.systemTemp.createTemp(
        'employee-attachment-conflict-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}retry.pdf');
      await file.writeAsBytes([1]);
      when(
        () => apiClient.postMap(any(), data: any(named: 'data')),
      ).thenThrow(const AppException.validation('attachment_storage_conflict'));

      await expectLater(
        repository.uploadAttachment(
          'employee-id',
          AttachmentUploadCandidate(
            path: file.path,
            name: 'retry.pdf',
            size: 1,
            extension: 'pdf',
          ),
        ),
        throwsA(
          isA<Failure>()
              .having((failure) => failure.type, 'type', FailureType.conflict)
              .having((failure) => failure.message, 'message', '附件暂时无法保存，请重试。'),
        ),
      );
    },
  );

  test('maps malformed metadata to a data failure', () async {
    final apiClient = _MockApiClient();
    final repository = NetworkAttachmentRepository(apiClient);
    when(
      () => apiClient.getMap(
        any(),
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => {
        'count': 1,
        'next': null,
        'previous': null,
        'results': [
          {..._attachmentJson, 'file_size': '1024'},
        ],
      },
    );

    await expectLater(
      repository.fetchAttachments('employee-id'),
      throwsA(
        isA<Failure>().having(
          (failure) => failure.type,
          'type',
          FailureType.data,
        ),
      ),
    );
  });
}
