import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../../departments/presentation/department_controller.dart';
import '../data/position.dart';
import 'position_management_controller.dart';

class PositionManagementPage extends ConsumerWidget {
  const PositionManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positions = ref.watch(positionListProvider);
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
                    '岗位管理',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                FilledButton.icon(
                  key: const Key('position_create'),
                  onPressed: () => _editPosition(context, ref, null),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新增岗位'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: positions.when(
                loading: () => const AppLoadingView(label: '正在加载岗位'),
                error: (error, _) => AppErrorView(
                  message: error is Failure ? error.message : '岗位加载失败，请稍后重试。',
                  onRetry: () => ref.invalidate(positionListProvider),
                ),
                data: (items) => items.isEmpty
                    ? const Center(child: Text('暂无岗位数据'))
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final position = items[index];
                          return Card(
                            child: ListTile(
                              title: Text(position.name),
                              subtitle: Text(
                                '${position.code} · ${position.department.name}',
                              ),
                              leading: const Icon(Icons.work_outline_rounded),
                              trailing: Wrap(
                                children: [
                                  IconButton(
                                    tooltip: '编辑岗位',
                                    onPressed: () =>
                                        _editPosition(context, ref, position),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: position.isActive
                                        ? '停用岗位'
                                        : '启用岗位',
                                    onPressed: () =>
                                        _setActive(context, ref, position),
                                    icon: Icon(
                                      position.isActive
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

  Future<void> _editPosition(
    BuildContext context,
    WidgetRef ref,
    Position? position,
  ) async {
    final departments =
        ref.read(departmentControllerProvider).value ?? const [];
    final activeDepartments = departments
        .where((item) => item.isActive)
        .toList();
    if (activeDepartments.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先创建启用部门。')));
      return;
    }
    final codeController = TextEditingController(text: position?.code ?? '');
    final nameController = TextEditingController(text: position?.name ?? '');
    var departmentId = position?.department.id ?? activeDepartments.first.id;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(position == null ? '新增岗位' : '编辑岗位'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(labelText: '岗位编号'),
                ),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '岗位名称'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: departmentId,
                  decoration: const InputDecoration(labelText: '所属部门'),
                  items: [
                    for (final department in activeDepartments)
                      DropdownMenuItem(
                        value: department.id,
                        child: Text(department.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => departmentId = value ?? departmentId),
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
      ),
    );
    if (accepted != true || !context.mounted) {
      return;
    }
    try {
      final data = {
        'code': codeController.text.trim(),
        'name': nameController.text.trim(),
        'department': departmentId,
      };
      final controller = ref.read(positionManagementControllerProvider);
      if (position == null) {
        await controller.create(data);
      } else {
        await controller.update(position.id, data);
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
    Position position,
  ) async {
    try {
      await ref
          .read(positionManagementControllerProvider)
          .setActive(position.id, active: !position.isActive);
    } on Failure catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}
