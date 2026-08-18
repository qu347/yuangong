import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    await ref
        .read(authControllerProvider.notifier)
        .login(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final error = auth.error;
    final errorMessage = error is Failure ? error.message : null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.apartment_rounded,
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '登录员工目录',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '使用企业内部开发账号访问员工与部门目录。',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 28),
                        TextFormField(
                          key: const Key('login_username'),
                          controller: _usernameController,
                          enabled: !auth.isLoading,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          decoration: const InputDecoration(
                            labelText: '用户名或工作邮箱',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? '请输入用户名或工作邮箱'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('login_password'),
                          controller: _passwordController,
                          enabled: !auth.isLoading,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: auth.isLoading
                              ? null
                              : (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: '密码',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                              onPressed: auth.isLoading
                                  ? null
                                  : () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              value == null || value.isEmpty ? '请输入密码' : null,
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            errorMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          key: const Key('login_submit'),
                          onPressed: auth.isLoading ? null : _submit,
                          child: auth.isLoading
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Text('登录'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          key: const Key('login_accept_invitation'),
                          onPressed: auth.isLoading
                              ? null
                              : () => context.go('/forgot-password'),
                          child: const Text('忘记密码'),
                        ),
                        TextButton(
                          onPressed: auth.isLoading
                              ? null
                              : () => context.go('/accept-invitation'),
                          child: const Text('接受账号邀请'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
