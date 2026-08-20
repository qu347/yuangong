import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/app_breakpoints.dart';

class AppDestination {
  const AppDestination({
    required this.label,
    required this.path,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
}

const appDestinations = <AppDestination>[
  AppDestination(
    label: '工作台',
    path: '/dashboard',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard_rounded,
  ),
  AppDestination(
    label: '通讯录',
    path: '/employees',
    icon: Icons.badge_outlined,
    selectedIcon: Icons.badge_rounded,
  ),
  AppDestination(
    label: '部门',
    path: '/departments',
    icon: Icons.account_tree_outlined,
    selectedIcon: Icons.account_tree_rounded,
  ),
  AppDestination(
    label: '安全',
    path: '/settings/security',
    icon: Icons.security_outlined,
    selectedIcon: Icons.security_rounded,
  ),
  AppDestination(
    label: '通知',
    path: '/notifications',
    icon: Icons.notifications_none_rounded,
    selectedIcon: Icons.notifications_rounded,
  ),
];

class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({
    required this.currentPath,
    required this.onDestinationSelected,
    required this.child,
    this.onLogout,
    this.onLogoutAll,
    super.key,
  });

  final String currentPath;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;
  final VoidCallback? onLogout;
  final VoidCallback? onLogoutAll;

  int get _selectedIndex {
    final index = appDestinations.indexWhere(
      (destination) => currentPath.startsWith(destination.path),
    );
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppBreakpoints.desktop) {
          final extended = constraints.maxWidth >= AppBreakpoints.expandedRail;
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    extended: extended,
                    minExtendedWidth: 236,
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: onDestinationSelected,
                    leading: Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 22),
                      child: extended
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _BrandMark(),
                                SizedBox(width: 12),
                                Text(
                                  '员工管理',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            )
                          : const _BrandMark(),
                    ),
                    trailing: onLogout == null && onLogoutAll == null
                        ? null
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (onLogoutAll != null)
                                IconButton(
                                  key: const Key('shell_logout_all'),
                                  tooltip: '退出所有设备',
                                  onPressed: onLogoutAll,
                                  icon: const Icon(
                                    Icons.phonelink_erase_outlined,
                                  ),
                                ),
                              if (onLogout != null)
                                IconButton(
                                  key: const Key('shell_logout'),
                                  tooltip: '退出登录',
                                  onPressed: onLogout,
                                  icon: const Icon(Icons.logout_rounded),
                                ),
                            ],
                          ),
                    destinations: [
                      for (final destination in appDestinations)
                        NavigationRailDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.selectedIcon),
                          label: Text(destination.label),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      _DesktopTopBar(currentPath: currentPath),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 20,
            title: const Row(
              children: [
                _BrandMark(size: 30),
                SizedBox(width: 10),
                Text('企业员工管理系统'),
              ],
            ),
            actions: [
              IconButton(
                key: const Key('shell_search'),
                tooltip: '全局搜索',
                onPressed: () => context.go('/search'),
                icon: const Icon(Icons.search_rounded),
              ),
              IconButton(
                tooltip: '通知中心',
                onPressed: () => context.go('/notifications'),
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              if (onLogoutAll != null)
                IconButton(
                  key: const Key('shell_logout_all'),
                  tooltip: '退出所有设备',
                  onPressed: onLogoutAll,
                  icon: const Icon(Icons.phonelink_erase_outlined),
                ),
              if (onLogout != null)
                IconButton(
                  key: const Key('shell_logout'),
                  tooltip: '退出登录',
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout_rounded),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: [
              for (final destination in appDestinations)
                NavigationDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: destination.label,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({required this.currentPath});
  final String currentPath;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE0E5E3))),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                key: const Key('shell_search'),
                borderRadius: BorderRadius.circular(24),
                onTap: () => context.go('/search'),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F4F3),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.search_rounded, size: 20),
                      SizedBox(width: 10),
                      Text('搜索员工、部门或岗位'),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '通知中心',
              onPressed: currentPath == '/notifications'
                  ? null
                  : () => context.go('/notifications'),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        Icons.apartment_rounded,
        color: Theme.of(context).colorScheme.onPrimary,
        size: size * 0.58,
      ),
    );
  }
}
