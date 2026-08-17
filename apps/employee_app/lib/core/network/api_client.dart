import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../config/app_config.dart';
import '../errors/app_exception.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  return ApiClient(baseUrl: '${config.apiBaseUrl}/');
});

class ApiClient {
  ApiClient({required String baseUrl, Dio? dio, Logger? logger})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              headers: const {'Accept': 'application/json'},
            ),
          ),
      _logger = logger ?? Logger();

  final Dio _dio;
  final Logger _logger;

  Future<Map<String, dynamic>> getMap(String path) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(path);
      final data = response.data;
      if (data == null) {
        throw const AppException.protocol('empty response');
      }
      return data;
    } on DioException catch (error) {
      _logger.w('API request failed: path=$path type=${error.type.name}');
      if (error.response?.statusCode == 503) {
        throw const AppException.protocol('service unavailable');
      }
      throw const AppException.network('request failed');
    }
  }
}
