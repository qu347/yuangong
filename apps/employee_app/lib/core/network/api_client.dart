import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../config/app_config.dart';
import '../errors/app_exception.dart';
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
      final match = RegExp(r'filename="?([^";]+)').firstMatch(disposition);
      final candidate = match?.group(1) ?? 'audit-events.csv';
      final filename = RegExp(r'^[A-Za-z0-9._-]+[.]csv$').hasMatch(candidate)
          ? candidate
          : 'audit-events.csv';
      return ApiDownload(bytes: Uint8List.fromList(data), filename: filename);
    } on DioException catch (error) {
      throw _mapDioException(path, error);
    }
  }

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
      409 => AppException.conflict(_safeErrorCode(error.response?.data)),
      503 => const AppException.protocol('service unavailable'),
      _ => const AppException.network('request failed'),
    };
  }

  String _safeErrorCode(Object? payload) {
    if (payload case {'code': final String code}) {
      return code;
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
