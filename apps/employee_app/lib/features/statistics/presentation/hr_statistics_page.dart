import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../data/hr_statistics.dart';
import 'hr_statistics_controller.dart';

class HrStatisticsPage extends ConsumerWidget {
  const HrStatisticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statistics = ref.watch(hrStatisticsControllerProvider);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () =>
            ref.read(hrStatisticsControllerProvider.notifier).retry(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'HR 统计',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '查看组织规模、入职趋势和基础人员分布。',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  statistics.when(
                    loading: () => const AppLoadingView(label: '正在加载 HR 统计'),
                    error: (error, _) => AppErrorView(
                      message: error is Failure
                          ? error.message
                          : 'HR 统计加载失败，请稍后重试。',
                      onRetry: () => ref
                          .read(hrStatisticsControllerProvider.notifier)
                          .retry(),
                    ),
                    data: (value) => _StatisticsContent(statistics: value),
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

class _StatisticsContent extends StatelessWidget {
  const _StatisticsContent({required this.statistics});

  final HrStatistics statistics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth >= 600
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _MetricCard(
                    label: '员工总数',
                    value: statistics.employeeTotal,
                    icon: Icons.groups_outlined,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _MetricCard(
                    label: '岗位统计',
                    value: statistics.positionTotal,
                    icon: Icons.work_outline,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        _SectionCard(
          title: '部门人数统计',
          child: _CountBars(
            rows: [
              for (final item in statistics.departmentHeadcount)
                _CountRow(label: item.name, count: item.count, suffix: '人'),
            ],
            emptyLabel: '暂无部门人数数据',
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: '入职趋势',
          child: _CountBars(
            rows: [
              for (final item in statistics.hireTrend)
                _CountRow(label: item.month, count: item.count, suffix: '人'),
            ],
            emptyLabel: '暂无入职趋势数据',
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: '基础人员分析',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 640
                  ? (constraints.maxWidth - 20) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  SizedBox(
                    width: width,
                    child: _AnalysisGroup(
                      title: '性别分布',
                      values: statistics.genderDistribution,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _AnalysisGroup(
                      title: '年龄分布',
                      values: statistics.ageDistribution,
                    ),
                  ),
                ],
              );
            },
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _CountRow {
  const _CountRow({
    required this.label,
    required this.count,
    required this.suffix,
  });

  final String label;
  final int count;
  final String suffix;
}

class _CountBars extends StatelessWidget {
  const _CountBars({required this.rows, required this.emptyLabel});

  final List<_CountRow> rows;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text(emptyLabel);
    }
    final maximum = rows.fold<int>(
      1,
      (value, row) => row.count > value ? row.count : value,
    );
    return Column(
      children: [
        for (final row in rows) ...[
          Row(
            children: [
              Expanded(child: Text(row.label)),
              Text('${row.count} ${row.suffix}'),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: row.count / maximum,
            minHeight: 9,
            borderRadius: BorderRadius.circular(99),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _AnalysisGroup extends StatelessWidget {
  const _AnalysisGroup({required this.title, required this.values});

  final String title;
  final List<StatisticsCount> values;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        if (values.isEmpty)
          const Text('暂无数据')
        else
          for (final item in values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text(_localizedLabel(item.label))),
                  Text('${item.count} 人'),
                ],
              ),
            ),
      ],
    );
  }
}

String _localizedLabel(String label) => switch (label) {
  'female' => '女',
  'male' => '男',
  '29_and_under' => '29 岁及以下',
  '30_39' => '30–39 岁',
  '40_49' => '40–49 岁',
  '50_plus' => '50 岁及以上',
  _ => label,
};
