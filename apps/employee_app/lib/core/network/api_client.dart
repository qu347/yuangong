import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../config/app_config.dart';
import '../errors/app_exception.dart';
import '../files/safe_filename.dart';
import '../storage/token_storage.dart';
import 'api_endpoints.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final client = ApiClient(
    baseUrl: '${config.apiBaseUrl}/',
    tokenStorage: ref.watch(tokenStorageProvider),
  );
  ref.onDispose(client.close);
  return client;
});

class ApiDownload {
  const ApiDownload({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

class ApiFileDownload {
  const ApiFileDownload({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    required TokenStorage tokenStorage,
    Dio? dio,
    Dio? refreshDio,
    Logger? logger,
  }) : _tokenStorage = tokenStorage,
       _dio = dio ?? Dio(),
       _refreshDio = refreshDio ?? Dio(),
       _logger = logger ?? Logger() {
    _configureDio(_dio, baseUrl);
    _configureDio(_refreshDio, baseUrl);
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  static const _skipAuthKey = 'skip_auth';
  static const _retriedAfterRefreshKey = 'retried_after_refresh';

  final Dio _dio;
  final Dio _refreshDio;
  final TokenStorage _tokenStorage;
  final Logger _logger;
  final StreamController<void> _authenticationLostController =
      StreamController<void>.broadcast();

  Future<void>? _refreshFuture;

  Stream<void> get authenticationLost => _authenticationLostController.stream;

  void _configureDio(Dio dio, String baseUrl) {
    dio.options.baseUrl = baseUrl;
    dio.options.connectTimeout = const Duration(seconds: 8);
    dio.options.receiveTimeout = const Duration(seconds: 8);
    dio.options.headers['Accept'] = 'application/json';
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[_skipAuthKey] == true) {
      handler.next(options);
      return;
    }

    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken != null && accessToken.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final options = error.requestOptions;
    final shouldRefresh =
        error.response?.statusCode == 401 &&
        options.extra[_skipAuthKey] != true &&
        options.extra[_retriedAfterRefreshKey] != true;
    if (!shouldRefresh) {
      handler.next(error);
      return;
    }

    try {
      await _refreshAccessToken();
      final accessToken = await _tokenStorage.readAccessToken();
      if (accessToken == null || accessToken.isEmpty) {
        throw const AppException.unauthorized('missing refreshed access token');
      }
      options.headers['Authorization'] = 'Bearer $accessToken';
      options.extra[_retriedAfterRefreshKey] = true;
      final requestData = options.data;
      if (requestData is FormData) {
        options.data = requestData.clone();
      }
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on AppException catch (refreshError) {
      handler.reject(
        DioException(
          requestOptions: options,
          response: error.response,
          type: DioExceptionType.badResponse,
          error: refreshError,
        ),
      );
    }
  }

  Future<void> _refreshAccessToken() {
    final existing = _refreshFuture;
    if (existing != null) {
      return existing;
    }

    final operation = _performRefresh();
    _refreshFuture = operation;
    return operation.whenComplete(() {
      if (identical(_refreshFuture, operation)) {
        _refreshFuture = null;
      }
    });
  }

  Future<void> _performRefresh() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _loseAuthentication();
      throw const AppException.unauthorized('missing refresh token');
    }

    try {
      final response = await _refreshDio.post<Map<String, dynamic>>(
        ApiEndpoints.refresh,
        data: {'refresh': refreshToken},
        options: Options(extra: const {_skipAuthKey: true}),
      );
      final data = response.data;
      final accessToken = data?['access'];
      if (accessToken is! String || accessToken.isEmpty) {
        throw const AppException.protocol('invalid refresh response');
      }
      final rotatedRefreshToken = data?['refresh'];
      if (rotatedRefreshToken is String && rotatedRefreshToken.isNotEmpty) {
        await _tokenStorage.saveTokens(
          accessToken: accessToken,
          refreshToken: rotatedRefreshToken,
        );
      } else {
        await _tokenStorage.saveAccessToken(accessToken);
      }
    } on Object {
      await _loseAuthentication();
      throw const AppException.unauthorized('refresh failed');
    }
  }

  Future<void> _loseAuthentication() async {
    await _tokenStorage.clear();
    if (!_authenticationLostController.isClosed) {
      _authenticationLostController.add(null);
    }
  }

  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
      );
      final data = response.data;
      if (data == null) {
        throw const AppException.protocol('empty response');
      }
      return data;
    } on DioException catch (error) {
      throw _mapDioException(path, error);
    }
  }

  Future<List<dynamic>> getList(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        path,
        queryParameters: queryParameters,
      );
      final data = response.data;
      if (data == null) {
        throw const AppException.protocol('empty response');
      }
      return data;
    } on DioException catch (error) {
      throw _mapDioException(path, error);
    }
  }

  Future<ApiDownload> downloadBytes(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final download = await downloadFile(
      path,
      queryParameters: queryParameters,
      fallbackFilename: 'audit-events.csv',
      allowedExtensions: const {'csv'},
    );
    return ApiDownload(bytes: download.bytes, filename: download.filename);
  }

  Future<ApiFileDownload> downloadFile(
    String path, {
    Map<String, dynamic>? queryParameters,
    required String fallbackFilename,
    required Set<String> allowedExtensions,
  }) async {
    final normalizedExtensions = allowedExtensions
        .map((extension) => extension.toLowerCase())
        .toSet();
    if (!SafeFilenamePolicy.isSafe(
      fallbackFilename,
      allowedExtensions: normalizedExtensions,
    )) {
      throw const AppException.protocol('invalid fallback filename');
    }
    try {
      final response = await _dio.get<List<int>>(
        path,
        queryParameters: queryParameters,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null) {
        throw const AppException.protocol('empty download response');
      }
      final disposition = response.headers.value('content-disposition') ?? '';
      final filename =
          _filenameFromDisposition(disposition, normalizedExtensions) ??
          fallbackFilename;
      final contentType = response.headers.value(Headers.contentTypeHeader);
      final mimeType = contentType?.split(';').first.trim().toLowerCase();
      return ApiFileDownload(
        bytes: Uint8List.fromList(data),
        filename: filename,
        mimeType: mimeType == null || mimeType.isEmpty
            ? 'application/octet-stream'
            : mimeType,
      );
    } on DioException catch (error) {
      throw _mapDioException(path, error);
    }
  }

  String? _filenameFromDisposition(
    String disposition,
    Set<String> allowedExtensions,
  ) {
    final extended = _dispositionParameter(disposition, 'filename*');
    final decoded = extended == null ? null : _decodeRfc5987(extended);
    if (decoded != null &&
        SafeFilenamePolicy.isSafe(
          decoded,
          allowedExtensions: allowedExtensions,
        )) {
      return decoded;
    }

    final plain = _dispositionParameter(disposition, 'filename');
    if (plain != null &&
        SafeFilenamePolicy.isSafe(
          plain,
          allowedExtensions: allowedExtensions,
        )) {
      return plain;
    }
    return null;
  }

  String? _dispositionParameter(String disposition, String name) {
    final match = RegExp(
      '(?:^|;)\\s*${RegExp.escape(name)}\\s*=\\s*'
      '(?:"([^"]*)"|([^;]*))',
      caseSensitive: false,
    ).firstMatch(disposition);
    return (match?.group(1) ?? match?.group(2))?.trim();
  }

  String? _decodeRfc5987(String value) {
    final match = RegExp(r"^([^']*)'([^']*)'(.*)$").firstMatch(value);
    if (match == null || match.group(1)!.toLowerCase() != 'utf-8') {
      return null;
    }
    final encoded = match.group(3)!;
    for (var index = 0; index < encoded.length; index += 1) {
      if (encoded.codeUnitAt(index) != 0x25) {
        continue;
      }
      if (index + 2 >= encoded.length ||
          !_isHexDigit(encoded.codeUnitAt(index + 1)) ||
          !_isHexDigit(encoded.codeUnitAt(index + 2))) {
        return null;
      }
      index += 2;
    }
    try {
      return Uri.decodeComponent(encoded);
    } on FormatException {
      return null;
    }
  }

  bool _isHexDigit(int codeUnit) =>
      (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x46) ||
      (codeUnit >= 0x61 && codeUnit <= 0x66);

  Future<Map<String, dynamic>> postMap(
    String path, {
    Object? data,
    bool authenticated = true,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        data: data,
        options: Options(extra: {_skipAuthKey: !authenticated}),
      );
      final payload = response.data;
      if (payload == null) {
        throw const AppException.protocol('empty response');
      }
      return payload;
    } on DioException catch (error) {
      throw _mapDioException(path, error);
    }
  }

  Future<Map<String, dynamic>> patchMap(String path, {Object? data}) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(path, data: data);
      final payload = response.data;
      if (payload == null) {
        throw const AppException.protocol('empty response');
      }
      return payload;
    } on DioException catch (error) {
      throw _mapDioException(path, error);
    }
  }

  Future<void> postVoid(
    String path, {
    Object? data,
    bool authenticated = true,
  }) async {
    try {
      await _dio.post<void>(
        path,
        data: data,
        options: Options(extra: {_skipAuthKey: !authenticated}),
      );
    } on DioException catch (error) {
      throw _mapDioException(path, error);
    }
  }

  Future<void> deleteVoid(String path) async {
    try {
      await _dio.delete<void>(path);
    } on DioException catch (error) {
      throw _mapDioException(path, error);
    }
  }

  AppException _mapDioException(String path, DioException error) {
    _logger.w(
      'API request failed: path=$path type=${error.type.name} '
      'status=${error.response?.statusCode ?? 'none'}',
    );
    final nestedError = error.error;
    if (nestedError is AppException) {
      return nestedError;
    }
    return switch (error.response?.statusCode) {
      400 => AppException.validation(_safeErrorCode(error.response?.data)),
      401 => const AppException.unauthorized('authentication required'),
      403 => const AppException.forbidden('permission denied'),
      404 => AppException.validation(_safeErrorCode(error.response?.data)),
      409 => AppException.conflict(_safeErrorCode(error.response?.data)),
      503 => const AppException.protocol('service unavailable'),
      _ => const AppException.network('request failed'),
    };
  }

  String _safeErrorCode(Object? payload) {
    if (payload case {'code': final String code}) {
      return code;
    }
    if (payload is List<int> && payload.length <= 64 * 1024) {
      try {
        return _safeErrorCode(jsonDecode(utf8.decode(payload)));
      } on FormatException {
        return 'conflict';
      }
    }
    return 'conflict';
  }

  void close() {
    _authenticationLostController.close();
    _dio.close(force: true);
    if (!identical(_dio, _refreshDio)) {
      _refreshDio.close(force: true);
    }
  }
}
