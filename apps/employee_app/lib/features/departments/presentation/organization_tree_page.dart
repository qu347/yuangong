import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../../employees/data/employee.dart';
import '../data/organization_tree_repository.dart';
import 'organization_tree_controller.dart';

class OrganizationTreePage extends ConsumerWidget {
  const OrganizationTreePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(organizationTreeControllerProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('组织架构', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            const Text('按部门层级查看状态与员工人数。'),
            const SizedBox(height: 18),
            Expanded(
              child: tree.when(
                loading: () =>
                    const Center(child: AppLoadingView(label: '正在加载组织架构')),
                error: (error, _) => Center(
                  child: AppErrorView(
                    message: error is Failure
                        ? error.message
                        : '组织架构加载失败，请稍后重试。',
                    onRetry: () => ref
                        .read(organizationTreeControllerProvider.notifier)
                        .retry(),
                  ),
                ),
                data: (nodes) => nodes.isEmpty
                    ? const Center(child: Text('暂无组织架构'))
                    : ListView(
                        children: [
                          for (final node in nodes) _TreeNodeTile(node: node),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TreeNodeTile extends StatelessWidget {
  const _TreeNodeTile({required this.node});
  final OrganizationTreeNode node;

  @override
  Widget build(BuildContext context) {
    final title = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showDepartmentMembers(context, node),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(node.name)),
            Text('${node.employeeCount} 人'),
            const SizedBox(width: 8),
            Chip(label: Text(node.isActive ? '启用' : '停用')),
          ],
        ),
      ),
    );
    if (node.children.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.apartment_outlined),
          title: title,
          subtitle: Text(node.code),
          onTap: () => _showDepartmentMembers(context, node),
        ),
      );
    }
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.account_tree_outlined),
        title: title,
        subtitle: Text(node.code),
        childrenPadding: const EdgeInsets.only(left: 20, right: 8, bottom: 8),
        children: [
          for (final child in node.children) _TreeNodeTile(node: child),
        ],
      ),
    );
  }
}

Future<void> _showDepartmentMembers(
  BuildContext context,
  OrganizationTreeNode department,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.72,
      child: _DepartmentMembersSheet(department: department),
    ),
  );
}

class _DepartmentMembersSheet extends ConsumerWidget {
  const _DepartmentMembersSheet({required this.department});

  final OrganizationTreeNode department;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(departmentMembersProvider(department.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${department.name}成员',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text('${department.employeeCount} 人 · ${department.code}'),
          const SizedBox(height: 16),
          Expanded(
            child: members.when(
              loading: () =>
                  const Center(child: AppLoadingView(label: '正在加载部门成员')),
              error: (error, _) => Center(
                child: AppErrorView(
                  message: error is Failure ? error.message : '部门成员加载失败，请稍后重试。',
                  onRetry: () =>
                      ref.invalidate(departmentMembersProvider(department.id)),
                ),
              ),
              data: (items) => items.isEmpty
                  ? const Center(child: Text('该部门暂无员工'))
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _MemberCard(employee: items[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(employee.fullName.characters.first)),
        title: Text(employee.fullName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(employee.employeeNo),
            if (employee.workEmail.isNotEmpty) Text(employee.workEmail),
            Text(employee.position?.name ?? '未分配岗位'),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go('/employees/${employee.id}'),
      ),
    );
  }
}
