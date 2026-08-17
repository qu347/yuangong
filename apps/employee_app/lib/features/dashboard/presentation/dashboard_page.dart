import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../health/presentation/health_controller.dart';
import '../../health/presentation/health_status_card.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final health = ref.watch(healthControllerProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('工作台', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  '欢迎使用企业员工管理系统。当前阶段仅开放工程连通检查。',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 28),
                HealthStatusCard(
                  health: health,
                  config: config,
                  onRetry: () => ref.invalidate(healthControllerProvider),
                ),
                const SizedBox(height: 28),
                Text('功能概览', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                const _ModuleNotice(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModuleNotice extends StatelessWidget {
  const _ModuleNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0EE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.construction_outlined, color: Color(0xFF526763)),
          SizedBox(width: 14),
          Expanded(child: Text('通讯录、考勤、审批、公告与个人中心已建立模块边界，业务功能将在后续迭代中开发。')),
        ],
      ),
    );
  }
}
