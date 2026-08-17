import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/responsive/app_breakpoints.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../../departments/presentation/department_controller.dart';
import '../data/employee.dart';
import '../data/employee_page.dart';
import 'employee_directory_controller.dart';

class EmployeeListPage extends ConsumerWidget {
  const EmployeeListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(employeeDirectoryControllerProvider);
    final controller = ref.read(employeeDirectoryControllerProvider.notifier);
    final departments =
        ref.watch(departmentControllerProvider).value ?? const [];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '员工目录',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '搜索并查看企业内部工作通讯信息。',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: '刷新员工目录',
                  onPressed: controller.refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    key: const Key('employee_search'),
                    onChanged: controller.setSearch,
                    decoration: const InputDecoration(
                      labelText: '搜索姓名、工号或工作邮箱',
                      prefixIcon: Icon(Icons.search_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    key: const Key('employee_department_filter'),
                    initialValue: state.query.departmentId ?? '',
                    decoration: const InputDecoration(
                      labelText: '部门',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('全部部门')),
                      for (final department in departments)
                        DropdownMenuItem(
                          value: department.id,
                          child: Text(department.name),
                        ),
                    ],
                    onChanged: (value) {
                      controller.setDepartment(
                        value == null || value.isEmpty ? null : value,
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    key: const Key('employee_status_filter'),
                    initialValue: state.query.status ?? '',
                    decoration: const InputDecoration(
                      labelText: '在职状态',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('全部状态')),
                      DropdownMenuItem(value: 'active', child: Text('在职')),
                      DropdownMenuItem(value: 'departed', child: Text('离职')),
                    ],
                    onChanged: (value) {
                      controller.setStatus(
                        value == null || value.isEmpty ? null : value,
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: state.page.when(
                loading: () =>
                    const Center(child: AppLoadingView(label: '正在加载员工目录')),
                error: (error, _) => Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: AppErrorView(
                      message: error is Failure
                          ? error.message
                          : '员工目录加载失败，请稍后重试。',
                      onRetry: controller.retry,
                    ),
                  ),
                ),
                data: (page) => page.results.isEmpty
                    ? const _EmptyEmployeeView()
                    : _EmployeeResults(page: page),
              ),
            ),
            if (state.page.value case final page? when page.results.isNotEmpty)
              _PaginationBar(
                count: page.count,
                page: state.query.page,
                hasPrevious: page.hasPrevious,
                hasNext: page.hasNext,
                onPrevious: controller.previousPage,
                onNext: controller.nextPage,
              ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeResults extends StatelessWidget {
  const _EmployeeResults({required this.page});

  final EmployeePage page;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppBreakpoints.desktop) {
          return SingleChildScrollView(
            child: SizedBox(
              width: double.infinity,
              child: DataTable(
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('姓名')),
                  DataColumn(label: Text('工号')),
                  DataColumn(label: Text('部门')),
                  DataColumn(label: Text('岗位')),
                  DataColumn(label: Text('状态')),
                ],
                rows: [
                  for (final employee in page.results)
                    DataRow(
                      key: ValueKey('employee_row_${employee.employeeNo}'),
                      onSelectChanged: (_) =>
                          context.go('/employees/${employee.id}'),
                      cells: [
                        DataCell(Text(employee.fullName)),
                        DataCell(Text(employee.employeeNo)),
                        DataCell(Text(employee.department.name)),
                        DataCell(Text(employee.position?.name ?? '未分配')),
                        DataCell(_StatusBadge(employee: employee)),
                      ],
                    ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          itemCount: page.results.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final employee = page.results[index];
            return Card(
              key: Key('employee_card_${employee.employeeNo}'),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => context.go('/employees/${employee.id}'),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      CircleAvatar(
                        child: Text(employee.fullName.characters.first),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              employee.fullName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${employee.employeeNo} · ${employee.department.name}',
                            ),
                            const SizedBox(height: 2),
                            Text(employee.position?.name ?? '未分配岗位'),
                          ],
                        ),
                      ),
                      _StatusBadge(employee: employee),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final active = employee.isActive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFDDF3EC) : const Color(0xFFF0E8E4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? '在职' : '离职',
        style: TextStyle(
          color: active ? const Color(0xFF08775F) : const Color(0xFF7A5142),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyEmployeeView extends StatelessWidget {
  const _EmptyEmployeeView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_search_outlined, size: 48),
          SizedBox(height: 14),
          Text('没有符合条件的员工'),
        ],
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.count,
    required this.page,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
  });

  final int count;
  final int page;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('共 $count 人 · 第 $page 页'),
          const SizedBox(width: 12),
          IconButton(
            tooltip: '上一页',
            onPressed: hasPrevious ? onPrevious : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: '下一页',
            onPressed: hasNext ? onNext : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}
