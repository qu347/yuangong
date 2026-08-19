import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../employees/data/employee_repository.dart';
import '../data/account_repository.dart';

final invitationEmployeeProvider = FutureProvider.autoDispose(
  (ref) => ref
      .watch(employeeRepositoryProvider)
      .fetchEmployees(status: 'active', pageSize: 100),
  retry: (retryCount, error) => null,
);

class InvitationFormPage extends ConsumerStatefulWidget {
  const InvitationFormPage({super.key});
  @override
  ConsumerState<InvitationFormPage> createState() => _InvitationFormPageState();
}

class _InvitationFormPageState extends ConsumerState<InvitationFormPage> {
  final username = TextEditingController();
  final email = TextEditingController();
  String? employeeId;
  String role = 'employee';
  bool submitting = false;
  bool dirty = false;
  String? error;

  @override
  void dispose() {
    username.dispose();
    email.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (submitting ||
        employeeId == null ||
        username.text.trim().isEmpty ||
        email.text.trim().isEmpty) {
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await ref
          .read(accountRepositoryProvider)
          .createInvitation(
            employeeId: employeeId!,
            username: username.text,
            email: email.text,
            role: role,
          );
      dirty = false;
      if (mounted) context.pop();
    } on Failure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  void markDirty([Object? _]) {
    if (!dirty) setState(() => dirty = true);
  }

  Future<void> requestLeave() async {
    if (submitting) return;
    if (dirty && !await confirmDiscardUnsavedChanges(context)) return;
    if (!mounted) return;
    setState(() => dirty = false);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/admin/accounts');
    }
  }

  @override
  Widget build(BuildContext context) {
    final employees = ref.watch(invitationEmployeeProvider);
    return PopScope(
      canPop: !dirty && !submitting,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && !submitting) await requestLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: requestLeave),
          title: const Text('创建账号邀请'),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: [
                  employees.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => const Text('员工加载失败'),
                    data: (page) => DropdownButtonFormField<String>(
                      initialValue: employeeId,
                      decoration: const InputDecoration(labelText: '在职员工'),
                      items: [
                        for (final employee in page.results.where(
                          (item) => item.isActive,
                        ))
                          DropdownMenuItem(
                            value: employee.id,
                            child: Text(
                              '${employee.employeeNo} · ${employee.fullName}',
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        employeeId = value;
                        dirty = true;
                      }),
                    ),
                  ),
                  TextField(
                    controller: username,
                    onChanged: markDirty,
                    decoration: const InputDecoration(labelText: '登录名'),
                  ),
                  TextField(
                    controller: email,
                    onChanged: markDirty,
                    decoration: const InputDecoration(labelText: '账号邮箱'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: '角色'),
                    items: const [
                      DropdownMenuItem(
                        value: 'employee',
                        child: Text('employee'),
                      ),
                      DropdownMenuItem(
                        value: 'hr_admin',
                        child: Text('hr_admin'),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      role = value ?? role;
                      dirty = true;
                    }),
                  ),
                  if (error != null) Text(error!),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: submitting ? null : submit,
                    child: Text(submitting ? '正在发送' : '发送邀请'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
