import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account_security/presentation/accept_invitation_page.dart';
import '../../features/account_security/presentation/forgot_password_page.dart';
import '../../features/account_security/presentation/reset_password_page.dart';
import '../../features/account_security/presentation/security_settings_page.dart';
import '../../features/account_security/presentation/session_list_page.dart';
import '../../features/accounts/presentation/account_detail_page.dart';
import '../../features/accounts/presentation/account_list_page.dart';
import '../../features/accounts/presentation/invitation_form_page.dart';
import '../../features/attachments/presentation/attachment_page.dart';
import '../../features/attachments/presentation/attachment_upload_page.dart';
import '../../features/audit/presentation/audit_page.dart';
import '../../features/authentication/presentation/auth_controller.dart';
import '../../features/authentication/presentation/auth_session_store.dart';
import '../../features/authentication/presentation/login_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/departments/presentation/department_management_page.dart';
import '../../features/departments/presentation/organization_tree_page.dart';
import '../../features/employees/presentation/employee_detail_page.dart';
import '../../features/employees/presentation/employee_form_page.dart';
import '../../features/employees/presentation/employee_list_page.dart';
import '../../features/notifications/presentation/notification_page.dart';
import '../../features/positions/presentation/position_management_page.dart';
import '../../features/search/presentation/global_search_page.dart';
import '../../features/shell/presentation/adaptive_shell.dart';
import '../../features/statistics/presentation/hr_statistics_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = createAppRouter(
    ref.watch(authSessionStoreProvider),
    onLogout: () {
      unawaited(ref.read(authControllerProvider.notifier).logout());
    },
    onLogoutAll: () {
      unawaited(ref.read(authControllerProvider.notifier).logoutAll());
    },
  );
  ref.onDispose(router.dispose);
  return router;
});

GoRouter createAppRouter(
  AuthSessionStore sessionStore, {
  String initialLocation = '/login',
  VoidCallback? onLogout,
  VoidCallback? onLogoutAll,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: sessionStore,
    redirect: (context, state) {
      final onLogin = state.matchedLocation == '/login';
      final publicRecovery = {
        '/forgot-password',
        '/reset-password',
        '/accept-invitation',
      }.contains(state.matchedLocation);
      if (sessionStore.status != AuthSessionStatus.authenticated) {
        return onLogin || publicRecovery ? null : '/login';
      }
      final location = state.matchedLocation;
      final capabilities = sessionStore.capabilities;
      if ((location == '/employees/new' || location.endsWith('/edit')) &&
          !capabilities.canManageEmployees) {
        return '/employees';
      }
      if (location.endsWith('/attachments/upload') &&
          !capabilities.canManageEmployees) {
        return '/employees';
      }
      if (location.endsWith('/attachments') &&
          !capabilities.canManageEmployees &&
          state.pathParameters['id'] != sessionStore.employeeId) {
        return '/employees';
      }
      if (location == '/departments/manage' &&
          !capabilities.canManageDepartments) {
        return '/employees';
      }
      if (location == '/positions/manage' && !capabilities.canManagePositions) {
        return '/employees';
      }
      if (location == '/audit' && !capabilities.canViewAudit) {
        return '/employees';
      }
      if (location == '/statistics' && !capabilities.canViewAudit) {
        return '/employees';
      }
      if ((location == '/settings/sessions' && !capabilities.canViewSessions) ||
          (location == '/settings/security' &&
              !capabilities.canChangePassword)) {
        return '/employees';
      }
      if (location.startsWith('/admin/') && !capabilities.canManageAccounts) {
        return '/employees';
      }
      return onLogin ? '/dashboard' : null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordPage(),
      ),
      GoRoute(
        path: '/accept-invitation',
        builder: (context, state) => const AcceptInvitationPage(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return AdaptiveShell(
            currentPath: state.uri.path,
            onDestinationSelected: (index) {
              context.go(appDestinations[index].path);
            },
            onLogout: onLogout,
            onLogoutAll: sessionStore.capabilities.canLogoutAll
                ? onLogoutAll
                : null,
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
            path: '/employees/new',
            builder: (context, state) => const EmployeeFormPage(),
          ),
          GoRoute(
            path: '/employees/:id/edit',
            builder: (context, state) =>
                EmployeeFormPage(employeeId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/employees/:id/attachments/upload',
            builder: (context, state) =>
                AttachmentUploadPage(employeeId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/employees/:id/attachments',
            builder: (context, state) =>
                AttachmentPage(employeeId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/employees/:id',
            builder: (context, state) =>
                EmployeeDetailPage(employeeId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/departments',
            builder: (context, state) => const OrganizationTreePage(),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => const GlobalSearchPage(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationPage(),
          ),
          GoRoute(
            path: '/statistics',
            builder: (context, state) => const HrStatisticsPage(),
          ),
          GoRoute(
            path: '/departments/manage',
            builder: (context, state) => const DepartmentManagementPage(),
          ),
          GoRoute(
            path: '/positions/manage',
            builder: (context, state) => const PositionManagementPage(),
          ),
          GoRoute(
            path: '/audit',
            builder: (context, state) => const AuditPage(),
          ),
          GoRoute(
            path: '/settings/security',
            builder: (context, state) => const SecuritySettingsPage(),
          ),
          GoRoute(
            path: '/settings/sessions',
            builder: (context, state) => const SessionListPage(),
          ),
          GoRoute(
            path: '/admin/accounts',
            builder: (context, state) => const AccountListPage(),
          ),
          GoRoute(
            path: '/admin/accounts/:id',
            builder: (context, state) =>
                AccountDetailPage(accountId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/admin/invitations/new',
            builder: (context, state) => const InvitationFormPage(),
          ),
        ],
      ),
    ],
  );
}
