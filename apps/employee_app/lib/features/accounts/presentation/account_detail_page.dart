import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../data/account.dart';
import 'account_controller.dart';

class AccountDetailPage extends ConsumerStatefulWidget {
  const AccountDetailPage({required this.accountId, super.key});

  final String accountId;

  @override
  ConsumerState<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends ConsumerState<AccountDetailPage> {
  final email = TextEditingController();
  String? initializedAccountId;
  bool busy = false;

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountDetailProvider(widget.accountId));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: account.when(
          loading: () => const AppLoadingView(label: '正在加载账号详情'),
          error: (error, _) => AppErrorView(
            message: error is Failure ? error.message : '账号详情加载失败。',
            onRetry: () =>
                ref.invalidate(accountDetailProvider(widget.accountId)),
          ),
          data: _buildAccount,
        ),
      ),
    );
  }

  Widget _buildAccount(Account value) {
    if (initializedAccountId != value.id) {
      initializedAccountId = value.id;
      email.text = value.email;
    }
    return ListView(
      children: [
        Text(value.username, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        ListTile(
          title: const Text('关联员工'),
          subtitle: Text(value.employee?.fullName ?? '无'),
        ),
        if (value.emailMismatch)
          const ListTile(
            leading: Icon(Icons.warning_amber_rounded),
            title: Text('账号邮箱与员工目录邮箱不一致'),
          ),
        if (!value.isManageable)
          const Card(
            child: ListTile(
              leading: Icon(Icons.lock_outline_rounded),
              title: Text('受保护账号'),
              subtitle: Text('超级用户和 system_admin 不能通过业务界面修改。'),
            ),
          )
        else ...[
          TextField(
            key: const Key('account_email'),
            controller: email,
            enabled: !busy,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: '账号邮箱'),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              key: const Key('account_email_save'),
              onPressed: busy ? null : () => _saveEmail(value),
              child: const Text('保存账号邮箱'),
            ),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            key: const Key('account_role'),
            initialValue: value.role == 'hr_admin' ? 'hr_admin' : 'employee',
            decoration: const InputDecoration(labelText: '受管角色'),
            items: const [
              DropdownMenuItem(value: 'employee', child: Text('employee')),
              DropdownMenuItem(value: 'hr_admin', child: Text('hr_admin')),
            ],
            onChanged: busy ? null : (role) => _changeRole(value, role),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonal(
                key: Key(
                  value.isActive ? 'account_deactivate' : 'account_activate',
                ),
                onPressed: busy ? null : () => _setActive(value),
                child: Text(value.isActive ? '停用账号' : '恢复账号'),
              ),
              OutlinedButton(
                key: const Key('account_revoke_sessions'),
                onPressed: busy ? null : () => _revokeSessions(value),
                child: const Text('撤销全部会话'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _saveEmail(Account account) async {
    final value = email.text.trim();
    if (value.isEmpty) {
      _showMessage('账号邮箱不能为空。');
      return;
    }
    await _run(
      () => ref.read(accountControllerProvider).updateEmail(account.id, value),
      success: '账号邮箱已更新。',
    );
  }

  Future<void> _changeRole(Account account, String? role) async {
    if (role == null || role == account.role) return;
    if (!await _confirm(
      title: '确认调整角色？',
      body: '角色调整会立即撤销该账号的全部登录会话。',
      action: '确认调整',
    )) {
      return;
    }
    await _run(
      () => ref.read(accountControllerProvider).changeRole(account.id, role),
      success: '账号角色已更新。',
    );
  }

  Future<void> _setActive(Account account) async {
    final active = !account.isActive;
    if (!await _confirm(
      title: active ? '确认恢复账号？' : '确认停用账号？',
      body: active ? '恢复后仍需重新登录。' : '停用后，该账号的全部会话会立即失效。',
      action: active ? '确认恢复' : '确认停用',
    )) {
      return;
    }
    await _run(
      () => ref.read(accountControllerProvider).setActive(account.id, active),
      success: active ? '账号已恢复。' : '账号已停用。',
    );
  }

  Future<void> _revokeSessions(Account account) async {
    if (!await _confirm(
      title: '确认撤销全部会话？',
      body: '该账号需要在所有设备上重新登录。',
      action: '确认撤销',
    )) {
      return;
    }
    await _run(
      () => ref.read(accountControllerProvider).revokeSessions(account.id),
      success: '账号会话已撤销。',
    );
  }

  Future<void> _run(
    Future<Object?> Function() operation, {
    required String success,
  }) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await operation();
      if (mounted) _showMessage(success);
    } on Failure catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _confirm({
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
