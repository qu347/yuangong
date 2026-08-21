import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notification_repository.dart';

final notificationControllerProvider =
    AsyncNotifierProvider<NotificationController, NotificationPageData>(
      NotificationController.new,
      retry: (retryCount, error) => null,
    );

class NotificationController extends AsyncNotifier<NotificationPageData> {
  @override
  Future<NotificationPageData> build() =>
      ref.watch(notificationRepositoryProvider).fetchNotifications();

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      ref.read(notificationRepositoryProvider).fetchNotifications,
    );
  }

  Future<void> markRead(String id) async {
    final current = state.value;
    if (current == null) return;
    final updated = await ref.read(notificationRepositoryProvider).markRead(id);
    state = AsyncData(
      NotificationPageData(
        count: current.count,
        unreadCount: current.results.any((item) => item.id == id && !item.read)
            ? current.unreadCount - 1
            : current.unreadCount,
        results: [
          for (final item in current.results)
            if (item.id == id) updated else item,
        ],
      ),
    );
  }
}
