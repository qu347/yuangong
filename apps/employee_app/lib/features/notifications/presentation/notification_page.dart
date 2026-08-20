import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import 'notification_controller.dart';

class NotificationPage extends ConsumerWidget {
  const NotificationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationControllerProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('通知中心', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 18),
            Expanded(
              child: notifications.when(
                loading: () =>
                    const Center(child: AppLoadingView(label: '正在加载通知')),
                error: (error, _) => Center(
                  child: AppErrorView(
                    message: error is Failure ? error.message : '通知加载失败，请稍后重试。',
                    onRetry: () => ref
                        .read(notificationControllerProvider.notifier)
                        .retry(),
                  ),
                ),
                data: (page) {
                  if (page.results.isEmpty) {
                    return const Center(child: Text('暂无通知'));
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('未读 ${page.unreadCount} 条，共 ${page.count} 条'),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.separated(
                          itemCount: page.results.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = page.results[index];
                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  item.read
                                      ? Icons.notifications_none
                                      : Icons.notifications_active,
                                ),
                                title: Text(
                                  item.title,
                                  style: TextStyle(
                                    fontWeight: item.read
                                        ? FontWeight.normal
                                        : FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(item.content),
                                trailing: item.read
                                    ? const Text('已读')
                                    : TextButton(
                                        onPressed: () => ref
                                            .read(
                                              notificationControllerProvider
                                                  .notifier,
                                            )
                                            .markRead(item.id),
                                        child: const Text('标为已读'),
                                      ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
