import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/shell/presentation/adaptive_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        builder: (context, state, child) {
          return AdaptiveShell(
            currentPath: state.uri.path,
            onDestinationSelected: (index) {
              context.go(appDestinations[index].path);
            },
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/employees',
            builder: (context, state) => const PlaceholderPage(
              title: '通讯录',
              description: '员工档案与组织通讯能力将在后续迭代中开发。',
              icon: Icons.badge_outlined,
            ),
          ),
          GoRoute(
            path: '/attendance',
            builder: (context, state) => const PlaceholderPage(
              title: '考勤',
              description: '考勤规则与打卡方式尚待业务确认。',
              icon: Icons.schedule_outlined,
            ),
          ),
          GoRoute(
            path: '/approvals',
            builder: (context, state) => const PlaceholderPage(
              title: '审批',
              description: '请假、补卡与加班审批将在后续迭代中开发。',
              icon: Icons.fact_check_outlined,
            ),
          ),
          GoRoute(
            path: '/notices',
            builder: (context, state) => const PlaceholderPage(
              title: '公告',
              description: '企业公告与通知能力将在后续迭代中开发。',
              icon: Icons.campaign_outlined,
            ),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const PlaceholderPage(
              title: '我的',
              description: '个人资料与账户设置将在认证方案确认后开发。',
              icon: Icons.person_outline_rounded,
            ),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    required this.title,
    required this.description,
    required this.icon,
    super.key,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 20),
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 12),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
