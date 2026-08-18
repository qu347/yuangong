import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../authentication/presentation/auth_session_store.dart';
import 'account_security_controller.dart';
import 'password_fields.dart';

class SecuritySettingsPage extends ConsumerStatefulWidget {
  const SecuritySettingsPage({super.key});
  @override
  ConsumerState<SecuritySettingsPage> createState() =>
      _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends ConsumerState<SecuritySettingsPage> {
  final current = TextEditingController();
  final next = TextEditingController();
  bool submitting = false;

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    super.dispose();
  }

  Future<void> changePassword() async {
    if (submitting ||
        validateStrongPassword(next.text) != null ||
        current.text.isEmpty) {
      return;
    }
    setState(() => submitting = true);
    try {
      await ref
          .read(accountSecurityControllerProvider)
          .changePassword(current.text, next.text);
    } on Failure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      current.clear();
      next.clear();
      if (mounted) {
        setState(() => submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = ref.watch(authSessionStoreProvider).capabilities;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('安全设置', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        SecurePasswordField(
                          controller: current,
                          label: '当前密码',
                          validator: (v) =>
                              v == null || v.isEmpty ? '请输入当前密码' : null,
                        ),
                        const SizedBox(height: 12),
                        SecurePasswordField(controller: next, label: '新密码'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: submitting ? null : changePassword,
                          child: const Text('修改密码并重新登录'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.go('/settings/sessions'),
                  icon: const Icon(Icons.devices_outlined),
                  label: const Text('管理登录设备'),
                ),
                if (capabilities.canManageAccounts) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    key: const Key('account_admin_entry'),
                    onPressed: () => context.go('/admin/accounts'),
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: const Text('账号管理'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
