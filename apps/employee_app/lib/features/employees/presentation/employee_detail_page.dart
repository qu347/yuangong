import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../data/employee.dart';
import '../data/employee_repository.dart';

final employeeDetailProvider = FutureProvider.family<Employee, String>(
  (ref, id) => ref.watch(employeeRepositoryProvider).fetchEmployee(id),
  retry: (retryCount, error) => null,
);

class EmployeeDetailPage extends ConsumerWidget {
  const EmployeeDetailPage({required this.employeeId, super.key});

  final String employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(employeeDetailProvider(employeeId));

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
                  data: (value) => _EmployeeDetailCard(employee: value),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
