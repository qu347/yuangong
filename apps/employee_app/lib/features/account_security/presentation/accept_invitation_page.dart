import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import 'account_security_controller.dart';
import 'password_fields.dart';

class AcceptInvitationPage extends ConsumerStatefulWidget {
  const AcceptInvitationPage({super.key});
  @override
  ConsumerState<AcceptInvitationPage> createState() =>
      _AcceptInvitationPageState();
}

class _AcceptInvitationPageState extends ConsumerState<AcceptInvitationPage> {
  final formKey = GlobalKey<FormState>();
  final token = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool submitting = false;
  String? error;

  @override
  void dispose() {
    token.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (submitting || !formKey.currentState!.validate()) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await ref
          .read(accountSecurityControllerProvider)
          .acceptInvitation(token.text, password.text);
      token.clear();
      password.clear();
      confirm.clear();
      if (mounted) context.go('/login');
    } on Failure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('接受账号邀请')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Form(
            key: formKey,
            child: Column(
              children: [
                TextFormField(
                  key: const Key('invitation_token'),
                  controller: token,
                  enabled: !submitting,
                  decoration: const InputDecoration(
                    labelText: '一次性邀请码',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请输入邀请码' : null,
                ),
                const SizedBox(height: 12),
                SecurePasswordField(
                  controller: password,
                  label: '新密码',
                  enabled: !submitting,
                ),
                const SizedBox(height: 12),
                SecurePasswordField(
                  controller: confirm,
                  label: '确认新密码',
                  enabled: !submitting,
                  validator: (value) =>
                      value != password.text ? '两次密码不一致' : null,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(error!),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('invitation_accept_submit'),
                  onPressed: submitting ? null : submit,
                  child: Text(submitting ? '正在提交' : '设置初始密码'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
