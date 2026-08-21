import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.content,
    required this.read,
    required this.createdAt,
  });
  final String id;
  final String title;
  final String content;
  final bool read;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final read = json['read'];
    final createdAt = DateTime.tryParse(_requiredString(json, 'created_at'));
    if (read is! bool || createdAt == null) {
      throw const FormatException('invalid notification');
    }
    return AppNotification(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      content: _requiredString(json, 'content'),
      read: read,
      createdAt: createdAt,
    );
  }
}

class NotificationPageData {
  const NotificationPageData({
    required this.count,
    required this.unreadCount,
    required this.results,
  });
  final int count;
  final int unreadCount;
  final List<AppNotification> results;
  factory NotificationPageData.fromJson(Map<String, dynamic> json) {
    final count = json['count'];
    final unread = json['unread_count'];
    final results = json['results'];
    if (count is! int || unread is! int || results is! List) {
      throw const FormatException('invalid notification page');
    }
    return NotificationPageData(
      count: count,
      unreadCount: unread,
      results: List.unmodifiable(
        results.map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('invalid notification item');
          }
          return AppNotification.fromJson(item);
        }),
      ),
    );
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NetworkNotificationRepository(ref.watch(apiClientProvider)),
);

abstract interface class NotificationRepository {
  Future<NotificationPageData> fetchNotifications({
    int page = 1,
    int pageSize = 20,
  });
  Future<AppNotification> markRead(String id);
}

class NetworkNotificationRepository implements NotificationRepository {
  const NetworkNotificationRepository(this._client);
  final ApiClient _client;

  @override
  Future<NotificationPageData> fetchNotifications({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      return NotificationPageData.fromJson(
        await _client.getMap(
          ApiEndpoints.notifications,
          queryParameters: {'page': page, 'page_size': pageSize},
        ),
      );
    } on AppException catch (error) {
      if (error.type == AppExceptionType.network) {
        throw const Failure.network();
      }
      throw const Failure.service();
    } on FormatException {
      throw const Failure.data();
    }
  }

  @override
  Future<AppNotification> markRead(String id) async {
    try {
      return AppNotification.fromJson(
        await _client.patchMap('${ApiEndpoints.notifications}$id/read/'),
      );
    } on AppException catch (error) {
      if (error.type == AppExceptionType.network) {
        throw const Failure.network();
      }
      throw const Failure.service();
    } on FormatException {
      throw const Failure.data();
    }
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('invalid $key');
  }
  return value;
}
