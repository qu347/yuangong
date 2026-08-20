import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

enum SearchResultType { employee, department, position }

class GlobalSearchResult {
  const GlobalSearchResult({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
  });
  final SearchResultType type;
  final String id;
  final String title;
  final String subtitle;

  factory GlobalSearchResult.fromJson(Map<String, dynamic> json) {
    final type = SearchResultType.values
        .where((value) => value.name == json['type'])
        .firstOrNull;
    if (type == null) {
      throw const FormatException('invalid search type');
    }
    return GlobalSearchResult(
      type: type,
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      subtitle: _string(json, 'subtitle'),
    );
  }
}

class GlobalSearchPageData {
  const GlobalSearchPageData({required this.count, required this.results});
  final int count;
  final List<GlobalSearchResult> results;

  factory GlobalSearchPageData.fromJson(Map<String, dynamic> json) {
    final count = json['count'];
    final results = json['results'];
    if (count is! int || results is! List) {
      throw const FormatException('invalid search page');
    }
    return GlobalSearchPageData(
      count: count,
      results: List.unmodifiable(
        results.map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('invalid search item');
          }
          return GlobalSearchResult.fromJson(item);
        }),
      ),
    );
  }
}

final globalSearchRepositoryProvider = Provider<GlobalSearchRepository>(
  (ref) => NetworkGlobalSearchRepository(ref.watch(apiClientProvider)),
);

abstract interface class GlobalSearchRepository {
  Future<GlobalSearchPageData> search(
    String query, {
    int page = 1,
    int pageSize = 20,
  });
}

class NetworkGlobalSearchRepository implements GlobalSearchRepository {
  const NetworkGlobalSearchRepository(this._client);
  final ApiClient _client;

  @override
  Future<GlobalSearchPageData> search(
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      return GlobalSearchPageData.fromJson(
        await _client.getMap(
          ApiEndpoints.globalSearch,
          queryParameters: {
            'q': query.trim(),
            'page': page,
            'page_size': pageSize,
          },
        ),
      );
    } on AppException catch (error) {
      throw _failure(error);
    } on FormatException {
      throw const Failure.data();
    }
  }
}

Failure _failure(AppException error) => switch (error.type) {
  AppExceptionType.network => const Failure.network(),
  AppExceptionType.unauthorized => const Failure.authentication(),
  AppExceptionType.forbidden => const Failure.permission(),
  AppExceptionType.validation => const Failure.validation('请输入有效的搜索关键词。'),
  AppExceptionType.conflict => const Failure.conflict(),
  AppExceptionType.protocol => const Failure.service(),
  AppExceptionType.unexpected => const Failure(
    type: FailureType.unexpected,
    message: '搜索失败，请稍后重试。',
  ),
};

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('invalid $key');
  }
  return value;
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('invalid $key');
  }
  return value;
}
