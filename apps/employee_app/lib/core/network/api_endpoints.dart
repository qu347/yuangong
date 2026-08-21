abstract final class ApiEndpoints {
  static const health = 'health/';
  static const dashboardSummary = 'dashboard/summary/';
  static const hrStatistics = 'statistics/hr/';
  static const globalSearch = 'search/';
  static const departmentTree = 'departments/tree/';
  static const notifications = 'notifications/';
  static const login = 'auth/login/';
  static const refresh = 'auth/refresh/';
  static const logout = 'auth/logout/';
  static const logoutAll = 'auth/logout-all/';
  static const me = 'me/';
  static const departments = 'departments/';
  static const positions = 'positions/';
  static const employees = 'employees/';
  static const auditEvents = 'audit-events/';
  static const auditExport = 'audit-events/export.csv';
  static const invitationAccept = 'auth/invitations/accept/';
  static const passwordResetRequest = 'auth/password-reset/request/';
  static const passwordResetConfirm = 'auth/password-reset/confirm/';
  static const passwordChange = 'auth/password/change/';
  static const sessions = 'auth/sessions/';
  static const revokeOtherSessions = 'auth/sessions/revoke-others/';
  static const accounts = 'accounts/';
  static const invitations = 'accounts/invitations/';

  static String employeeAttachments(String employeeId) =>
      '$employees$employeeId/attachments/';

  static String attachment(String attachmentId) => 'attachments/$attachmentId/';

  static String attachmentDownload(String attachmentId) =>
      '${attachment(attachmentId)}download/';
}
