import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../data/account.dart';
import 'account_controller.dart';

class AccountListPage extends ConsumerWidget {
  const AccountListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountListProvider);
    final invitations = ref.watch(invitationListProvider);
    return DefaultTabController(
      length: 2,
      child: SafeArea(
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
              const SizedBox(height: 14),
              const TabBar(
                tabs: [
                  Tab(text: '登录账号'),
                  Tab(text: '邀请管理'),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: TabBarView(
                  children: [
                    _AccountPanel(accounts: accounts),
                    _InvitationPanel(invitations: invitations),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountPanel extends ConsumerWidget {
  const _AccountPanel({required this.accounts});

  final AsyncValue<AccountPage> accounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) => accounts.when(
    loading: () => const AppLoadingView(label: '正在加载账号'),
    error: (error, _) => AppErrorView(
      message: error is Failure ? error.message : '账号加载失败。',
      onRetry: () => ref.invalidate(accountListProvider),
    ),
    data: (page) => page.results.isEmpty
        ? const Center(child: Text('暂无账号'))
        : ListView.separated(
            key: const Key('account_list'),
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
                  trailing: Chip(label: Text(account.isActive ? '启用' : '停用')),
                  onTap: () => context.push('/admin/accounts/${account.id}'),
                ),
              );
            },
          ),
  );
}

class _InvitationPanel extends ConsumerWidget {
  const _InvitationPanel({required this.invitations});

  final AsyncValue<List<AccountInvitation>> invitations;

  @override
  Widget build(BuildContext context, WidgetRef ref) => invitations.when(
    loading: () => const AppLoadingView(label: '正在加载邀请'),
    error: (error, _) => AppErrorView(
      message: error is Failure ? error.message : '邀请加载失败。',
      onRetry: () => ref.invalidate(invitationListProvider),
    ),
    data: (items) => items.isEmpty
        ? const Center(child: Text('暂无账号邀请'))
        : ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final invitation = items[index];
              final pending = invitation.status == 'pending';
              return Card(
                child: ListTile(
                  title: Text(invitation.username),
                  subtitle: Text(
                    '${invitation.email}\n${invitation.targetRole} · ${_statusLabel(invitation.status)}',
                  ),
                  isThreeLine: true,
                  trailing: pending
                      ? Wrap(
                          children: [
                            IconButton(
                              key: Key('invitation_resend_${invitation.id}'),
                              tooltip: '重发邀请',
                              onPressed: () =>
                                  _resend(context, ref, invitation),
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                            IconButton(
                              key: Key('invitation_revoke_${invitation.id}'),
                              tooltip: '撤销邀请',
                              onPressed: () =>
                                  _revoke(context, ref, invitation),
                              icon: const Icon(Icons.block_rounded),
                            ),
                          ],
                        )
                      : null,
                ),
              );
            },
          ),
  );

  Future<void> _resend(
    BuildContext context,
    WidgetRef ref,
    AccountInvitation invitation,
  ) async {
    if (!await _confirm(
      context,
      title: '确认重发邀请？',
      body: '旧邀请码会立即失效，并发送新的邀请邮件。',
      action: '确认重发',
    )) {
      return;
    }
    try {
      await ref.read(accountControllerProvider).resendInvitation(invitation.id);
      if (context.mounted) _showMessage(context, '邀请已重发。');
    } on Failure catch (error) {
      if (context.mounted) _showMessage(context, error.message);
    }
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    AccountInvitation invitation,
  ) async {
    if (!await _confirm(
      context,
      title: '确认撤销邀请？',
      body: '撤销后，该邀请码将立即失效。',
      action: '确认撤销',
    )) {
      return;
    }
    try {
      await ref.read(accountControllerProvider).revokeInvitation(invitation.id);
      if (context.mounted) _showMessage(context, '邀请已撤销。');
    } on Failure catch (error) {
      if (context.mounted) _showMessage(context, error.message);
    }
  }
}

String _statusLabel(String status) => switch (status) {
  'pending' => '待接受',
  'accepted' => '已接受',
  'revoked' => '已撤销',
  'expired' => '已过期',
  _ => status,
};

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
