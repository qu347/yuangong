import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:employee_app/core/errors/app_exception.dart';
import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/core/storage/token_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryTokenStorage implements TokenStorage {
  MemoryTokenStorage({this.accessToken, this.refreshToken});

  String? accessToken;
  String? refreshToken;
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount += 1;
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

typedef AdapterHandler = Future<ResponseBody> Function(RequestOptions options);

class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter(this.handler);

  final AdapterHandler handler;
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

ResponseBody jsonResponse(int statusCode, Map<String, dynamic> payload) {
  return ResponseBody.fromString(
    jsonEncode(payload),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

Dio dioWith(RecordingAdapter adapter) {
  return Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1/'))
    ..httpClientAdapter = adapter;
}

void main() {
  test('supports PATCH maps and 204 action responses', () async {
    final storage = MemoryTokenStorage(accessToken: 'access-test-value');
    final adapter = RecordingAdapter((options) async {
      if (options.method == 'PATCH') {
        return jsonResponse(200, {'name': '更新名称'});
      }
      return ResponseBody.fromString('', 204);
    });
    final client = ApiClient(
      baseUrl: 'https://api.example.test/api/v1/',
      tokenStorage: storage,
      dio: dioWith(adapter),
      refreshDio: dioWith(RecordingAdapter((_) async => jsonResponse(500, {}))),
    );
    addTearDown(client.close);

    final patched = await client.patchMap(
      'employees/employee-id/',
      data: {'full_name': '更新名称'},
    );
    await client.postVoid('employees/employee-id/depart/', data: const {});

    expect(patched, {'name': '更新名称'});
    expect(adapter.requests.map((request) => request.method), [
      'PATCH',
      'POST',
    ]);
  });

  test(
    'injects the stored access token without logging request data',
    () async {
      final storage = MemoryTokenStorage(
        accessToken: 'access-test-value',
        refreshToken: 'refresh-test-value',
      );
      final adapter = RecordingAdapter(
        (_) async => jsonResponse(200, {'ok': true}),
      );
      final refreshAdapter = RecordingAdapter(
        (_) async => jsonResponse(500, {'detail': 'unused'}),
      );
      final client = ApiClient(
        baseUrl: 'https://api.example.test/api/v1/',
        tokenStorage: storage,
        dio: dioWith(adapter),
        refreshDio: dioWith(refreshAdapter),
      );
      addTearDown(client.close);

      await client.getMap('employees/');

      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer access-test-value',
      );
    },
  );

  test(
    'coalesces concurrent 401 responses into one refresh and retries',
    () async {
      final storage = MemoryTokenStorage(
        accessToken: 'expired-access',
        refreshToken: 'stable-refresh',
      );
      final adapter = RecordingAdapter((options) async {
        if (options.headers['Authorization'] == 'Bearer fresh-access') {
          return jsonResponse(200, {'path': options.path});
        }
        return jsonResponse(401, {'detail': 'expired'});
      });
      var refreshCount = 0;
      final refreshAdapter = RecordingAdapter((options) async {
        refreshCount += 1;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(options.path, 'auth/refresh/');
        expect(options.data, {'refresh': 'stable-refresh'});
        return jsonResponse(200, {'access': 'fresh-access'});
      });
      final client = ApiClient(
        baseUrl: 'https://api.example.test/api/v1/',
        tokenStorage: storage,
        dio: dioWith(adapter),
        refreshDio: dioWith(refreshAdapter),
      );
      addTearDown(client.close);

      final results = await Future.wait([
        client.getMap('employees/'),
        client.getMap('profile/'),
      ]);

      expect(refreshCount, 1);
      expect(storage.accessToken, 'fresh-access');
      expect(results, [
        {'path': 'employees/'},
        {'path': 'profile/'},
      ]);
    },
  );

  test('clears tokens and emits auth loss when refresh is rejected', () async {
    final storage = MemoryTokenStorage(
      accessToken: 'expired-access',
      refreshToken: 'expired-refresh',
    );
    final adapter = RecordingAdapter(
      (_) async => jsonResponse(401, {'detail': 'expired'}),
    );
    final refreshAdapter = RecordingAdapter(
      (_) async => jsonResponse(401, {'detail': 'expired refresh'}),
    );
    final client = ApiClient(
      baseUrl: 'https://api.example.test/api/v1/',
      tokenStorage: storage,
      dio: dioWith(adapter),
      refreshDio: dioWith(refreshAdapter),
    );
    addTearDown(client.close);
    final authenticationLost = client.authenticationLost.first;

    await expectLater(
      client.getMap('employees/'),
      throwsA(
        isA<AppException>().having(
          (error) => error.type,
          'type',
          AppExceptionType.unauthorized,
        ),
      ),
    );

    await authenticationLost.timeout(const Duration(seconds: 1));
    expect(storage.clearCount, 1);
    expect(storage.accessToken, isNull);
    expect(storage.refreshToken, isNull);
  });
}
