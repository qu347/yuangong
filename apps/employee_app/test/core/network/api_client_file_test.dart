import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:employee_app/core/errors/app_exception.dart';
import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/core/storage/token_storage.dart';
import 'package:employee_app/features/attachments/data/attachment_repository.dart';
import 'package:employee_app/features/attachments/platform/attachment_file_saver.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryTokenStorage implements TokenStorage {
  _MemoryTokenStorage({
    this.accessToken = 'attachment-access-token',
    this.refreshToken,
  });

  String? accessToken;
  String? refreshToken;

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> saveAccessToken(String accessToken) async {
    this.accessToken = accessToken;
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }
}

typedef _AdapterHandler = Future<ResponseBody> Function(RequestOptions options);

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final _AdapterHandler handler;
  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }
}

typedef _BodyAdapterHandler =
    Future<ResponseBody> Function(RequestOptions options, Uint8List body);

class _BodyConsumingAdapter implements HttpClientAdapter {
  _BodyConsumingAdapter(this.handler);

  final _BodyAdapterHandler handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = BytesBuilder(copy: false);
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        body.add(chunk);
      }
    }
    return handler(options, body.takeBytes());
  }
}

Dio _dioWith(_RecordingAdapter adapter) {
  return Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1/'))
    ..httpClientAdapter = adapter;
}

ResponseBody _binaryResponse({
  String? disposition,
  String mimeType = 'application/pdf',
}) {
  final headers = <String, List<String>>{
    Headers.contentTypeHeader: [mimeType],
  };
  if (disposition != null) {
    headers['content-disposition'] = [disposition];
  }
  return ResponseBody.fromBytes([1, 2, 3], 200, headers: headers);
}

ApiClient _clientWith(_RecordingAdapter adapter) {
  return ApiClient(
    baseUrl: 'https://api.example.test/api/v1/',
    tokenStorage: _MemoryTokenStorage(),
    dio: _dioWith(adapter),
    refreshDio: _dioWith(
      _RecordingAdapter(
        (_) async =>
            ResponseBody.fromString(jsonEncode({'detail': 'unused'}), 500),
      ),
    ),
  );
}

void main() {
  test('multipart upload is rebuilt completely after a 401 refresh', () async {
    final storage = _MemoryTokenStorage(
      accessToken: 'expired-access',
      refreshToken: 'stable-refresh',
    );
    final requestBodies = <Uint8List>[];
    final adapter = _BodyConsumingAdapter((options, body) async {
      requestBodies.add(body);
      if (options.headers['Authorization'] == 'Bearer expired-access') {
        return ResponseBody.fromString(
          jsonEncode({'code': 'authentication_failed'}),
          401,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      return ResponseBody.fromString(
        jsonEncode({'ok': true}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });
    var refreshCount = 0;
    final refreshAdapter = _RecordingAdapter((_) async {
      refreshCount += 1;
      return ResponseBody.fromString(
        jsonEncode({'access': 'fresh-access'}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });
    final client = ApiClient(
      baseUrl: 'https://api.example.test/api/v1/',
      tokenStorage: storage,
      dio: Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1/'))
        ..httpClientAdapter = adapter,
      refreshDio: _dioWith(refreshAdapter),
    );
    addTearDown(client.close);
    const fileContent = 'COMPLETE-FILE-CONTENT';
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        utf8.encode(fileContent),
        filename: 'contract.pdf',
      ),
    });

    final response = await client.postMap(
      'employees/id/attachments/',
      data: formData,
    );

    expect(response, {'ok': true});
    expect(refreshCount, 1);
    expect(requestBodies, hasLength(2));
    for (final body in requestBodies) {
      final text = latin1.decode(body);
      expect(RegExp(r'name="file"').allMatches(text), hasLength(1));
      expect(RegExp(fileContent).allMatches(text), hasLength(1));
      expect(text, contains('filename="contract.pdf"'));
    }
    expect(requestBodies[1], requestBodies[0]);
  });

  test('generic download accepts a safe RFC 5987 Unicode basename', () async {
    final adapter = _RecordingAdapter(
      (_) async => _binaryResponse(
        disposition:
            "attachment; filename*=UTF-8''%E5%90%88%E5%90%8C%E6%89%AB%E6%8F%8F.pdf",
      ),
    );
    final client = _clientWith(adapter);
    addTearDown(client.close);

    final result = await client.downloadFile(
      'attachments/id/download/',
      fallbackFilename: 'attachment.pdf',
      allowedExtensions: const {'pdf'},
    );

    expect(result.bytes, [1, 2, 3]);
    expect(result.filename, '合同扫描.pdf');
    expect(result.mimeType, 'application/pdf');
    expect(adapter.requests.single.responseType, ResponseType.bytes);
  });

  test('RFC 5987 filename accepts an optional language field', () async {
    final adapter = _RecordingAdapter(
      (_) async => _binaryResponse(
        disposition: "attachment; filename*=uTf-8'zh-CN'%E5%90%88%E5%90%8C.pdf",
      ),
    );
    final client = _clientWith(adapter);
    addTearDown(client.close);

    final result = await client.downloadFile(
      'attachments/id/download/',
      fallbackFilename: 'attachment.pdf',
      allowedExtensions: const {'pdf'},
    );

    expect(result.filename, '合同.pdf');
  });

  test('invalid extended filenames fall back to safe plain filename', () async {
    final dispositions = [
      "attachment; filename*=UTF-8''bad%ZZ.pdf; filename=plain.pdf",
      "attachment; filename*=ISO-8859-1''report.pdf; filename=plain.pdf",
      "attachment; filename*=UTF-8''%2Fsecret.pdf; filename=plain.pdf",
      "attachment; filename*=UTF-8''%5Csecret.pdf; filename=plain.pdf",
    ];

    for (final disposition in dispositions) {
      final adapter = _RecordingAdapter(
        (_) async => _binaryResponse(disposition: disposition),
      );
      final client = _clientWith(adapter);
      addTearDown(client.close);

      final result = await client.downloadFile(
        'attachments/id/download/',
        fallbackFilename: 'attachment.pdf',
        allowedExtensions: const {'pdf'},
      );

      expect(result.filename, 'plain.pdf', reason: disposition);
    }
  });

  test('internal double-dot Unicode filename remains a safe basename', () async {
    final adapter = _RecordingAdapter(
      (_) async => _binaryResponse(
        disposition:
            "attachment; filename*=UTF-8''%E5%90%88%E5%90%8C..%F0%9F%98%80.docx",
        mimeType:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      ),
    );
    final client = _clientWith(adapter);
    addTearDown(client.close);

    final result = await client.downloadFile(
      'attachments/id/download/',
      fallbackFilename: 'attachment.docx',
      allowedExtensions: const {'docx'},
    );

    expect(result.filename, '合同..😀.docx');
  });

  test(
    'every non-PDF MIME remains savable when the response filename is missing or rejected',
    () async {
      const cases = [
        (
          fileType: 'docx',
          mimeType:
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ),
        (
          fileType: 'xlsx',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
        (fileType: 'jpg', mimeType: 'image/jpeg'),
        (fileType: 'png', mimeType: 'image/png'),
      ];

      for (final testCase in cases) {
        for (final disposition in <String?>[
          null,
          "attachment; filename*=UTF-8''..%2Funsafe.${testCase.fileType}",
        ]) {
          final adapter = _RecordingAdapter(
            (_) async => _binaryResponse(
              disposition: disposition,
              mimeType: testCase.mimeType,
            ),
          );
          final client = _clientWith(adapter);
          final repository = NetworkAttachmentRepository(client);
          final download = await repository.downloadAttachment(
            'attachment-id',
            fileType: testCase.fileType,
          );
          String? suggestedName;
          final saver = FileSelectorAttachmentFileSaver(
            platform: AttachmentSavePlatform.windows,
            chooseSavePath: (filename, _) async {
              suggestedName = filename;
              return 'C:\\downloads\\$filename';
            },
            writeFile: (_, _, _, _) async {},
          );

          final saved = await saver.save(
            download.bytes,
            download.filename,
            download.mimeType,
          );

          expect(download.filename, 'attachment.${testCase.fileType}');
          expect(suggestedName, download.filename);
          expect(saved.cancelled, isFalse);
          client.close();
        }
      }
    },
  );

  test('extended and plain Unicode format controls are rejected', () async {
    final dispositions = [
      "attachment; filename*=UTF-8''unsafe%C2%AD.pdf; filename=plain.pdf",
      "attachment; filename*=UTF-8''unsafe%D8%9C.pdf; filename=plain.pdf",
      "attachment; filename*=UTF-8''unsafe%E1%A0%8E.pdf; filename=plain.pdf",
      "attachment; filename*=UTF-8''unsafe%F3%A0%80%81.pdf; filename=plain.pdf",
      'attachment; filename="unsafe\u061C.pdf"',
    ];

    for (final disposition in dispositions) {
      final adapter = _RecordingAdapter(
        (_) async => _binaryResponse(disposition: disposition),
      );
      final client = _clientWith(adapter);
      addTearDown(client.close);

      final result = await client.downloadFile(
        'attachments/id/download/',
        fallbackFilename: 'attachment.pdf',
        allowedExtensions: const {'pdf'},
      );

      expect(
        result.filename,
        disposition.contains('filename=plain.pdf')
            ? 'plain.pdf'
            : 'attachment.pdf',
        reason: disposition,
      );
    }
  });

  test('generic download rejects traversal filename from headers', () async {
    final adapter = _RecordingAdapter(
      (_) async => _binaryResponse(
        disposition: 'attachment; filename="../../secret.pdf"',
      ),
    );
    final client = _clientWith(adapter);
    addTearDown(client.close);

    final result = await client.downloadFile(
      'attachments/id/download/',
      fallbackFilename: 'attachment.pdf',
      allowedExtensions: const {'pdf'},
    );

    expect(result.filename, 'attachment.pdf');
  });

  test('generic download enforces the caller extension allowlist', () async {
    final adapter = _RecordingAdapter(
      (_) async =>
          _binaryResponse(disposition: 'attachment; filename="report.exe"'),
    );
    final client = _clientWith(adapter);
    addTearDown(client.close);

    final result = await client.downloadFile(
      'attachments/id/download/',
      fallbackFilename: 'attachment.pdf',
      allowedExtensions: const {'pdf'},
    );

    expect(result.filename, 'attachment.pdf');
  });

  test('generic download rejects control characters in a filename', () async {
    final adapter = _RecordingAdapter(
      (_) async => _binaryResponse(
        disposition: 'attachment; filename="unsafe\u0000.pdf"',
      ),
    );
    final client = _clientWith(adapter);
    addTearDown(client.close);

    final result = await client.downloadFile(
      'attachments/id/download/',
      fallbackFilename: 'attachment.pdf',
      allowedExtensions: const {'pdf'},
    );

    expect(result.filename, 'attachment.pdf');
  });

  test('binary errors preserve stable JSON error codes', () async {
    final adapter = _RecordingAdapter(
      (_) async => ResponseBody.fromString(
        jsonEncode({'code': 'attachment_file_missing', 'message': '请求的资源不存在。'}),
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
    final client = _clientWith(adapter);
    addTearDown(client.close);

    await expectLater(
      client.downloadFile(
        'attachments/id/download/',
        fallbackFilename: 'attachment.pdf',
        allowedExtensions: const {'pdf'},
      ),
      throwsA(
        isA<AppException>().having(
          (error) => error.message,
          'message',
          'attachment_file_missing',
        ),
      ),
    );
  });

  test('deleteVoid sends DELETE and accepts a 204 response', () async {
    final adapter = _RecordingAdapter(
      (_) async => ResponseBody.fromString('', 204),
    );
    final client = _clientWith(adapter);
    addTearDown(client.close);

    await client.deleteVoid('attachments/id/');

    expect(adapter.requests.single.method, 'DELETE');
    expect(adapter.requests.single.path, 'attachments/id/');
  });

  test('existing audit download remains a CSV-compatible wrapper', () async {
    final adapter = _RecordingAdapter(
      (_) async => _binaryResponse(
        disposition: 'attachment; filename="audit-events-safe.csv"',
        mimeType: 'text/csv; charset=utf-8',
      ),
    );
    final client = _clientWith(adapter);
    addTearDown(client.close);

    final result = await client.downloadBytes(
      'audit-events/export.csv',
      queryParameters: const {'ordering': '-created_at'},
    );

    expect(result.filename, 'audit-events-safe.csv');
    expect(result.bytes, [1, 2, 3]);
    expect(adapter.requests.single.queryParameters, {
      'ordering': '-created_at',
    });
  });
}
