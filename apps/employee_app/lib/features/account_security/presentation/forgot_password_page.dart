import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import 'account_security_controller.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final controller = TextEditingController();
  bool submitting = false;
  String? message;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (submitting || controller.text.trim().isEmpty) return;
    setState(() => submitting = true);
    try {
      final result = await ref
          .read(accountSecurityControllerProvider)
          .requestReset(controller.text);
      if (mounted) setState(() => message = result);
    } on Failure catch (error) {
      if (mounted) setState(() => message = error.message);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('忘记密码')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('forgot_identifier'),
                controller: controller,
                enabled: !submitting,
                decoration: const InputDecoration(
                  labelText: '用户名或工作邮箱',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('forgot_submit'),
                onPressed: submitting ? null : submit,
                child: Text(submitting ? '正在提交' : '发送重置邮件'),
              ),
              if (message != null) ...[
                const SizedBox(height: 16),
                Text(message!, textAlign: TextAlign.center),
              ],
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('返回登录'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
