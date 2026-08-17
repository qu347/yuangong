import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../data/health_response.dart';

class HealthStatusCard extends StatelessWidget {
  const HealthStatusCard({
    required this.health,
    required this.config,
    required this.onRetry,
    super.key,
  });

  final AsyncValue<HealthResponse> health;
  final AppConfig config;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.monitor_heart_outlined,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '服务连接',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                _EnvironmentBadge(label: '环境 · ${config.appEnvironment}'),
              ],
            ),
            const SizedBox(height: 24),
            health.when(
              loading: () => const AppLoadingView(),
              error: (error, _) {
                final message = error is Failure
                    ? error.message
                    : '后端连接失败，请稍后重试。';
                return _StatusBody(
                  icon: Icons.cloud_off_outlined,
                  color: Theme.of(context).colorScheme.error,
                  title: '后端连接失败',
                  child: AppErrorView(message: message, onRetry: onRetry),
                );
              },
              data: (response) {
                if (!response.isHealthy) {
                  return _StatusBody(
                    icon: Icons.warning_amber_rounded,
                    color: const Color(0xFF9B5C00),
                    title: '后端连接失败',
                    child: AppErrorView(
                      message: '后端服务暂时不可用，请稍后重试。',
                      onRetry: onRetry,
                    ),
                  );
                }
                return _StatusBody(
                  icon: Icons.check_circle_outline_rounded,
                  color: const Color(0xFF08775F),
                  title: '后端连接正常',
                  child: Text(
                    '服务 ${response.service} · 版本 ${response.version}',
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 18),
            _DetailRow(label: '当前环境', value: config.appEnvironment),
            const SizedBox(height: 10),
            _DetailRow(label: 'API 地址', value: config.apiBaseUrl),
          ],
        ),
      ),
    );
  }
}

class _EnvironmentBadge extends StatelessWidget {
  const _EnvironmentBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0EE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: const Color(0xFF435653),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StatusBody extends StatelessWidget {
  const _StatusBody({
    required this.icon,
    required this.color,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final Color color;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF697A77)),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    );
  }
}
