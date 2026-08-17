import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../../authentication/presentation/auth_session_store.dart';
import '../data/department.dart';
import 'department_controller.dart';

class DepartmentPage extends ConsumerWidget {
  const DepartmentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departments = ref.watch(departmentControllerProvider);
    final capabilities = ref.watch(authSessionStoreProvider).capabilities;

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
                        '部门目录',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '查看启用状态和只读组织层级。',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
                if (capabilities.canManagePositions) ...[
                  FilledButton.tonalIcon(
                    key: const Key('position_manage_entry'),
                    onPressed: () => context.go('/positions/manage'),
                    icon: const Icon(Icons.work_outline_rounded),
                    label: const Text('岗位管理'),
                  ),
                  const SizedBox(width: 8),
                ],
                if (capabilities.canManageDepartments) ...[
                  FilledButton.icon(
                    key: const Key('department_manage_entry'),
                    onPressed: () => context.go('/departments/manage'),
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('部门管理'),
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton.filledTonal(
                  tooltip: '刷新部门目录',
                  onPressed: () =>
                      ref.read(departmentControllerProvider.notifier).retry(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: departments.when(
                loading: () =>
                    const Center(child: AppLoadingView(label: '正在加载部门目录')),
                error: (error, _) => Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: AppErrorView(
                      message: error is Failure
                          ? error.message
                          : '部门目录加载失败，请稍后重试。',
                      onRetry: () => ref
                          .read(departmentControllerProvider.notifier)
                          .retry(),
                    ),
                  ),
                ),
                data: (items) => items.isEmpty
                    ? const Center(child: Text('暂无部门数据'))
                    : _DepartmentHierarchy(departments: items),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentHierarchy extends StatelessWidget {
  const _DepartmentHierarchy({required this.departments});

  final List<Department> departments;

  @override
  Widget build(BuildContext context) {
    final byId = {
      for (final department in departments) department.id: department,
    };
    return ListView.separated(
      itemCount: departments.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final department = departments[index];
        final depth = _depthFor(department, byId);
        return Padding(
          key: Key('department_${department.id}'),
          padding: EdgeInsets.only(left: 16 + depth * 28, right: 4),
          child: Card(
            child: ListTile(
              leading: Icon(
                depth == 0
                    ? Icons.account_balance_outlined
                    : Icons.subdirectory_arrow_right_rounded,
              ),
              title: Text(department.name),
              subtitle: Text(department.code),
              trailing: Chip(label: Text(department.isActive ? '启用' : '停用')),
            ),
          ),
        );
      },
    );
  }

  int _depthFor(Department department, Map<String, Department> byId) {
    var depth = 0;
    var parentId = department.parentId;
    final visited = <String>{department.id};
    while (parentId != null && visited.add(parentId)) {
      final parent = byId[parentId];
      if (parent == null) {
        break;
      }
      depth += 1;
      parentId = parent.parentId;
    }
    return depth;
  }
}
