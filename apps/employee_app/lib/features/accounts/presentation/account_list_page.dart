import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import 'account_controller.dart';

class AccountListPage extends ConsumerWidget {
  const AccountListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountListProvider);
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
                    '账号管理',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                FilledButton.icon(
                  key: const Key('invitation_create_entry'),
                  onPressed: () => context.push('/admin/invitations/new'),
                  icon: const Icon(Icons.mail_outline_rounded),
                  label: const Text('创建邀请'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: accounts.when(
                loading: () => const AppLoadingView(label: '正在加载账号'),
                error: (error, _) => AppErrorView(
                  message: error is Failure ? error.message : '账号加载失败。',
                  onRetry: () => ref.invalidate(accountListProvider),
                ),
                data: (page) => page.results.isEmpty
                    ? const Center(child: Text('暂无账号'))
                    : ListView.separated(
                        itemCount: page.results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final account = page.results[index];
                          return Card(
                            child: ListTile(
                              title: Text(account.username),
                              subtitle: Text(
                                '${account.email}\n${account.employee?.fullName ?? '未关联员工'}',
                              ),
                              isThreeLine: true,
                              trailing: Chip(
                                label: Text(account.isActive ? '启用' : '停用'),
                              ),
                              onTap: () =>
                                  context.push('/admin/accounts/${account.id}'),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
