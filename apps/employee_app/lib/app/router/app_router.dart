import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/presentation/auth_controller.dart';
import '../../features/authentication/presentation/auth_session_store.dart';
import '../../features/authentication/presentation/login_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/departments/presentation/department_page.dart';
import '../../features/employees/presentation/employee_detail_page.dart';
import '../../features/employees/presentation/employee_list_page.dart';
import '../../features/shell/presentation/adaptive_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = createAppRouter(
    ref.watch(authSessionStoreProvider),
    onLogout: () {
      unawaited(ref.read(authControllerProvider.notifier).logout());
    },
  );
  ref.onDispose(router.dispose);
  return router;
});

GoRouter createAppRouter(
  AuthSessionStore sessionStore, {
  String initialLocation = '/login',
  VoidCallback? onLogout,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: sessionStore,
    redirect: (context, state) {
      final onLogin = state.matchedLocation == '/login';
      if (sessionStore.status != AuthSessionStatus.authenticated) {
        return onLogin ? null : '/login';
      }
      return onLogin ? '/employees' : null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      ShellRoute(
        builder: (context, state, child) {
          return AdaptiveShell(
            currentPath: state.uri.path,
            onDestinationSelected: (index) {
              context.go(appDestinations[index].path);
            },
            onLogout: onLogout,
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
            builder: (context, state) => const EmployeeListPage(),
          ),
          GoRoute(
            path: '/employees/:id',
            builder: (context, state) =>
                EmployeeDetailPage(employeeId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/departments',
            builder: (context, state) => const DepartmentPage(),
          ),
        ],
      ),
    ],
  );
}
