import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import 'account_controller.dart';

class AccountDetailPage extends ConsumerWidget {
  const AccountDetailPage({required this.accountId, super.key});
  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountDetailProvider(accountId));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: account.when(
          loading: () => const AppLoadingView(label: '正在加载账号详情'),
          error: (error, _) => AppErrorView(
            message: error is Failure ? error.message : '账号详情加载失败。',
            onRetry: () => ref.invalidate(accountDetailProvider(accountId)),
          ),
          data: (value) => ListView(
            children: [
              Text(
                value.username,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              ListTile(title: const Text('账号邮箱'), subtitle: Text(value.email)),
              ListTile(
                title: const Text('关联员工'),
                subtitle: Text(value.employee?.fullName ?? '无'),
              ),
              ListTile(
                title: const Text('角色'),
                subtitle: Text(value.role ?? '无受管角色'),
              ),
              if (value.emailMismatch)
                const ListTile(
                  leading: Icon(Icons.warning_amber_rounded),
                  title: Text('账号邮箱与员工目录邮箱不一致'),
                ),
              Wrap(
                spacing: 10,
                children: [
                  FilledButton.tonal(
                    onPressed: () => ref
                        .read(accountControllerProvider)
                        .setActive(value.id, !value.isActive),
                    child: Text(value.isActive ? '停用账号' : '恢复账号'),
                  ),
                  OutlinedButton(
                    onPressed: () => ref
                        .read(accountControllerProvider)
                        .changeRole(
                          value.id,
                          value.role == 'employee' ? 'hr_admin' : 'employee',
                        ),
                    child: const Text('切换 employee/hr_admin'),
                  ),
                  OutlinedButton(
                    onPressed: () => ref
                        .read(accountControllerProvider)
                        .revokeSessions(value.id),
                    child: const Text('撤销全部会话'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
