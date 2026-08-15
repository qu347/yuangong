import 'package:flutter/material.dart';

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
    label: '考勤',
    path: '/attendance',
    icon: Icons.schedule_outlined,
    selectedIcon: Icons.schedule_rounded,
  ),
  AppDestination(
    label: '审批',
    path: '/approvals',
    icon: Icons.fact_check_outlined,
    selectedIcon: Icons.fact_check_rounded,
  ),
  AppDestination(
    label: '公告',
    path: '/notices',
    icon: Icons.campaign_outlined,
    selectedIcon: Icons.campaign_rounded,
  ),
  AppDestination(
    label: '我的',
    path: '/profile',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
  ),
];

class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({
    required this.currentPath,
    required this.onDestinationSelected,
    required this.child,
    super.key,
  });

  final String currentPath;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

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
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                                ),
                              ],
                            )
                          : const _BrandMark(),
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
                Expanded(child: child),
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
