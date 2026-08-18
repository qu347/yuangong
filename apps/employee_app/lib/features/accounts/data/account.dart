class AccountEmployee {
  const AccountEmployee({
    required this.id,
    required this.employeeNo,
    required this.fullName,
    required this.employmentStatus,
    required this.workEmail,
  });

  final String id;
  final String employeeNo;
  final String fullName;
  final String employmentStatus;
  final String workEmail;

  factory AccountEmployee.fromJson(Map<String, dynamic> json) =>
      AccountEmployee(
        id: _string(json, 'id'),
        employeeNo: _string(json, 'employee_no'),
        fullName: _string(json, 'full_name'),
        employmentStatus: _string(json, 'employment_status'),
        workEmail: _string(json, 'work_email'),
      );
}

class Account {
  const Account({
    required this.id,
    required this.username,
    required this.email,
    required this.isActive,
    required this.lastLogin,
    required this.employee,
    required this.role,
    required this.hasActiveInvitation,
    required this.emailMismatch,
  });

  final String id;
  final String username;
  final String email;
  final bool isActive;
  final DateTime? lastLogin;
  final AccountEmployee? employee;
  final String? role;
  final bool hasActiveInvitation;
  final bool emailMismatch;

  factory Account.fromJson(Map<String, dynamic> json) {
    final employee = json['employee'];
    final active = json['is_active'];
    final invitation = json['has_active_invitation'];
    final mismatch = json['email_mismatch'];
    if (employee != null && employee is! Map<String, dynamic>) {
      throw const FormatException('invalid account employee');
    }
    if (active is! bool || invitation is! bool || mismatch is! bool) {
      throw const FormatException('invalid account flags');
    }
    final login = json['last_login'];
    return Account(
      id: _string(json, 'id'),
      username: _string(json, 'username'),
      email: _string(json, 'email'),
      isActive: active,
      lastLogin: login == null ? null : DateTime.tryParse(login as String),
      employee: employee == null
          ? null
          : AccountEmployee.fromJson(employee as Map<String, dynamic>),
      role: json['role'] as String?,
      hasActiveInvitation: invitation,
      emailMismatch: mismatch,
    );
  }
}

class AccountPage {
  const AccountPage({required this.count, required this.results});
  final int count;
  final List<Account> results;

  factory AccountPage.fromJson(Map<String, dynamic> json) {
    final count = json['count'];
    final results = json['results'];
    if (count is! int || results is! List) {
      throw const FormatException('invalid account page');
    }
    return AccountPage(
      count: count,
      results: List<Account>.unmodifiable(
        results.map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('invalid account item');
          }
          return Account.fromJson(item);
        }),
      ),
    );
  }
}

class AccountInvitation {
  const AccountInvitation({
    required this.id,
    required this.employeeId,
    required this.email,
    required this.username,
    required this.targetRole,
    required this.status,
    required this.expiresAt,
    required this.sendCount,
  });

  final String id;
  final String employeeId;
  final String email;
  final String username;
  final String targetRole;
  final String status;
  final DateTime expiresAt;
  final int sendCount;

  factory AccountInvitation.fromJson(Map<String, dynamic> json) =>
      AccountInvitation(
        id: _string(json, 'id'),
        employeeId: _string(json, 'employee_id'),
        email: _string(json, 'email'),
        username: _string(json, 'username'),
        targetRole: _string(json, 'target_role'),
        status: _string(json, 'status'),
        expiresAt: DateTime.parse(_string(json, 'expires_at')),
        sendCount: json['send_count'] as int,
      );
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('invalid $key');
  return value;
}
