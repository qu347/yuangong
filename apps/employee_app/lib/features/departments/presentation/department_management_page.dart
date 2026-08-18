import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../data/department.dart';
import 'department_controller.dart';
import 'department_management_controller.dart';

class DepartmentManagementPage extends ConsumerWidget {
  const DepartmentManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departments = ref.watch(departmentControllerProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '返回部门目录',
                  onPressed: () => context.go('/departments'),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '部门管理',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                FilledButton.icon(
                  key: const Key('department_create'),
                  onPressed: () => _editDepartment(context, ref, null),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新增部门'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: departments.when(
                loading: () => const AppLoadingView(label: '正在加载部门'),
                error: (error, _) => AppErrorView(
                  message: error is Failure ? error.message : '部门加载失败，请稍后重试。',
                  onRetry: () => ref.invalidate(departmentControllerProvider),
                ),
                data: (items) => items.isEmpty
                    ? const Center(child: Text('暂无部门数据'))
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final department = items[index];
                          return Card(
                            child: ListTile(
                              title: Text(department.name),
                              subtitle: Text(department.code),
                              leading: Icon(
                                department.isActive
                                    ? Icons.account_tree_outlined
                                    : Icons.pause_circle_outline_rounded,
                              ),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(
                                    tooltip: '编辑部门',
                                    onPressed: () => _editDepartment(
                                      context,
                                      ref,
                                      department,
                                    ),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: department.isActive
                                        ? '停用部门'
                                        : '启用部门',
                                    onPressed: () =>
                                        _setActive(context, ref, department),
                                    icon: Icon(
                                      department.isActive
                                          ? Icons.pause_circle_outline_rounded
                                          : Icons.play_circle_outline_rounded,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editDepartment(
    BuildContext context,
    WidgetRef ref,
    Department? department,
  ) async {
    final codeController = TextEditingController(text: department?.code ?? '');
    final nameController = TextEditingController(text: department?.name ?? '');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(department == null ? '新增部门' : '编辑部门'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('department_code'),
                controller: codeController,
                decoration: const InputDecoration(labelText: '部门编号'),
              ),
              TextField(
                key: const Key('department_name'),
                controller: nameController,
                decoration: const InputDecoration(labelText: '部门名称'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) {
      return;
    }
    try {
      final controller = ref.read(departmentManagementControllerProvider);
      final data = {
        'code': codeController.text.trim(),
        'name': nameController.text.trim(),
      };
      if (department == null) {
        await controller.create(data);
      } else {
        await controller.update(department.id, data);
      }
    } on Failure catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      codeController.dispose();
      nameController.dispose();
    }
  }

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    Department department,
  ) async {
    try {
      await ref
          .read(departmentManagementControllerProvider)
          .setActive(department.id, active: !department.isActive);
    } on Failure catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}
