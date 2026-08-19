import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../data/account_session.dart';
import 'account_security_controller.dart';

class SessionListPage extends ConsumerWidget {
  const SessionListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(accountSessionListProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '登录会话',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                OutlinedButton(
                  onPressed: () => ref
                      .read(accountSecurityControllerProvider)
                      .revokeOthers(),
                  child: const Text('撤销其他会话'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: sessions.when(
                loading: () => const AppLoadingView(label: '正在加载登录会话'),
                error: (error, _) => AppErrorView(
                  message: error is Failure ? error.message : '会话加载失败。',
                  onRetry: () => ref.invalidate(accountSessionListProvider),
                ),
                data: (items) => items.isEmpty
                    ? const Center(child: Text('暂无登录会话'))
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _SessionCard(session: items[index]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends ConsumerWidget {
  const _SessionCard({required this.session});
  final AccountSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: ListTile(
      leading: Icon(
        session.clientPlatform == 'windows'
            ? Icons.desktop_windows_outlined
            : Icons.phone_android_outlined,
      ),
      title: Text(
        session.clientName.isEmpty
            ? session.clientPlatform
            : session.clientName,
      ),
      subtitle: Text(
        '最近活动：${session.lastSeenAt.toLocal()}\n到期：${session.expiresAt.toLocal()}',
      ),
      isThreeLine: true,
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (session.isCurrent) const Chip(label: Text('当前设备')),
          IconButton(
            tooltip: '撤销会话',
            onPressed: () => ref
                .read(accountSecurityControllerProvider)
                .revokeSession(session),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
    ),
  );
}
