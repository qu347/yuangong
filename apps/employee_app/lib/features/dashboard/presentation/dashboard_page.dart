import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../../authentication/presentation/auth_session_store.dart';
import '../../health/presentation/health_controller.dart';
import '../../health/presentation/health_status_card.dart';
import '../data/dashboard_summary.dart';
import 'dashboard_controller.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final health = ref.watch(healthControllerProvider);
    final summary = ref.watch(dashboardControllerProvider);
    final canViewStatistics = ref
        .watch(authSessionStoreProvider)
        .capabilities
        .canViewAudit;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => ref.read(dashboardControllerProvider.notifier).retry(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '企业工作台',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '快速了解组织概况并进入常用工作。',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  summary.when(
                    loading: () => const AppLoadingView(label: '正在加载企业概况'),
                    error: (error, _) => AppErrorView(
                      message: error is Failure
                          ? error.message
                          : '企业概况加载失败，请稍后重试。',
                      onRetry: () => ref
                          .read(dashboardControllerProvider.notifier)
                          .retry(),
                    ),
                    data: (value) => _SummaryContent(
                      summary: value,
                      canViewStatistics: canViewStatistics,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text('系统状态', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  HealthStatusCard(
                    health: health,
                    config: config,
                    onRetry: () => ref.invalidate(healthControllerProvider),
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

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({
    required this.summary,
    required this.canViewStatistics,
  });
  final DashboardSummary summary;
  final bool canViewStatistics;

  @override
  Widget build(BuildContext context) {
    final cards = [
      ('员工总数', summary.employeeTotal, Icons.groups_outlined),
      ('在职员工', summary.activeEmployee, Icons.badge_outlined),
      ('部门数量', summary.departmentTotal, Icons.account_tree_outlined),
      ('岗位数量', summary.positionTotal, Icons.work_outline),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  SizedBox(
                    width: width,
                    child: _MetricCard(
                      label: card.$1,
                      value: card.$2,
                      icon: card.$3,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => context.go('/employees'),
              icon: const Icon(Icons.people_outline),
              label: const Text('员工目录'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => context.go('/search'),
              icon: const Icon(Icons.search),
              label: const Text('全局搜索'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => context.go('/departments'),
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('组织架构'),
            ),
            if (canViewStatistics)
              FilledButton.tonalIcon(
                onPressed: () => context.go('/statistics'),
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('HR统计'),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text('最近操作', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (summary.recentOperations.isEmpty)
          const Text('暂无可显示的最近操作')
        else
          Card(
            child: Column(
              children: [
                for (final operation in summary.recentOperations)
                  ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(
                      operation.resourceLabel.isEmpty
                          ? operation.resourceType
                          : operation.resourceLabel,
                    ),
                    subtitle: Text(operation.action),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(label),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
