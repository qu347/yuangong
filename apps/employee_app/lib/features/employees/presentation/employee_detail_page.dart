import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../../authentication/presentation/auth_session_store.dart';
import '../data/employee.dart';
import 'employee_management_controller.dart';

class EmployeeDetailPage extends ConsumerWidget {
  const EmployeeDetailPage({required this.employeeId, super.key});

  final String employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(employeeDetailProvider(employeeId));
    final canManage = ref
        .watch(authSessionStoreProvider)
        .capabilities
        .canManageEmployees;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '返回员工目录',
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/employees');
                        }
                      },
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '员工详情',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                employee.when(
                  loading: () => const Card(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: AppLoadingView(label: '正在加载员工详情'),
                    ),
                  ),
                  error: (error, _) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: AppErrorView(
                        message: error is Failure
                            ? error.message
                            : '员工详情加载失败，请稍后重试。',
                        onRetry: () =>
                            ref.invalidate(employeeDetailProvider(employeeId)),
                      ),
                    ),
                  ),
                  data: (value) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (canManage) ...[
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            OutlinedButton.icon(
                              key: const Key('employee_edit_entry'),
                              onPressed: () =>
                                  context.push('/employees/${value.id}/edit'),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('编辑员工'),
                            ),
                            FilledButton.tonalIcon(
                              key: const Key('employee_status_action'),
                              onPressed: () =>
                                  _changeStatus(context, ref, value),
                              icon: Icon(
                                value.isActive
                                    ? Icons.person_off_outlined
                                    : Icons.person_add_alt_outlined,
                              ),
                              label: Text(value.isActive ? '办理离职' : '恢复在职'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      _EmployeeDetailCard(employee: value),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    Employee employee,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(employee.isActive ? '确认办理离职？' : '确认恢复在职？'),
        content: Text(
          employee.isActive
              ? '离职会停用关联账号并吊销已登记的 Refresh Token。'
              : '恢复在职不会自动启用关联账号，账号仍需系统管理员处理。',
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      final controller = ref.read(employeeManagementControllerProvider);
      final result = employee.isActive
          ? await controller.depart(employee.id)
          : await controller.reactivate(employee.id);
      if (context.mounted) {
        final message = result.accountRequiresActivation
            ? '员工已恢复在职；关联账号仍保持停用。'
            : result.changed
            ? '员工状态已更新。'
            : '员工已经处于目标状态。';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } on Failure catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _EmployeeDetailCard extends StatelessWidget {
  const _EmployeeDetailCard({required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  child: Text(
                    employee.fullName.characters.first,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.fullName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(employee.employeeNo),
                    ],
                  ),
                ),
                Chip(label: Text(employee.isActive ? '在职' : '离职')),
              ],
            ),
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 12),
            _DetailRow(label: '工号', value: employee.employeeNo),
            _DetailRow(label: '工作邮箱', value: employee.workEmail),
            _DetailRow(label: '工作电话', value: employee.workPhone),
            _DetailRow(label: '部门', value: employee.department.name),
            _DetailRow(label: '岗位', value: employee.position?.name ?? '未分配'),
            _DetailRow(label: '在职状态', value: employee.isActive ? '在职' : '离职'),
            _DetailRow(label: '入职日期', value: _formatDate(employee.hireDate)),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime? date) {
  if (date == null) {
    return '未填写';
  }
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF697A77)),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
