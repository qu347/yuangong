class CurrentUserDepartment {
  const CurrentUserDepartment({
    required this.id,
    required this.code,
    required this.name,
  });

  final String id;
  final String code;
  final String name;

  factory CurrentUserDepartment.fromJson(Map<String, dynamic> json) {
    return CurrentUserDepartment(
      id: _requiredString(json, 'id'),
      code: _requiredString(json, 'code'),
      name: _requiredString(json, 'name'),
    );
  }
}

class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.employeeId,
    required this.employeeNo,
    required this.department,
    required this.roles,
    this.capabilities = const UserCapabilities.none(),
  });

  final String id;
  final String username;
  final String displayName;
  final String? employeeId;
  final String? employeeNo;
  final CurrentUserDepartment? department;
  final List<String> roles;
  final UserCapabilities capabilities;

  factory CurrentUser.fromJson(Map<String, dynamic> json) {
    final departmentJson = json['department'];
    final rolesJson = json['roles'];
    final capabilitiesJson = json['capabilities'];
    if (departmentJson != null && departmentJson is! Map<String, dynamic>) {
      throw const FormatException('invalid current user department');
    }
    if (rolesJson is! List || rolesJson.any((role) => role is! String)) {
      throw const FormatException('invalid current user roles');
    }
    if (capabilitiesJson != null && capabilitiesJson is! Map<String, dynamic>) {
      throw const FormatException('invalid current user capabilities');
    }
    return CurrentUser(
      id: _requiredString(json, 'id'),
      username: _requiredString(json, 'username'),
      displayName: _requiredString(json, 'display_name'),
      employeeId: _optionalString(json, 'employee_id'),
      employeeNo: _optionalString(json, 'employee_no'),
      department: departmentJson == null
          ? null
          : CurrentUserDepartment.fromJson(
              departmentJson as Map<String, dynamic>,
            ),
      roles: List<String>.unmodifiable(rolesJson.cast<String>()),
      capabilities: capabilitiesJson == null
          ? const UserCapabilities.none()
          : UserCapabilities.fromJson(capabilitiesJson as Map<String, dynamic>),
    );
  }
}

class UserCapabilities {
  const UserCapabilities({
    required this.canManageEmployees,
    required this.canManageDepartments,
    required this.canManagePositions,
    required this.canViewAudit,
    required this.canLogoutAll,
  });

  const UserCapabilities.none()
    : canManageEmployees = false,
      canManageDepartments = false,
      canManagePositions = false,
      canViewAudit = false,
      canLogoutAll = false;

  final bool canManageEmployees;
  final bool canManageDepartments;
  final bool canManagePositions;
  final bool canViewAudit;
  final bool canLogoutAll;

  bool get canManageDirectory =>
      canManageEmployees || canManageDepartments || canManagePositions;

  factory UserCapabilities.fromJson(Map<String, dynamic> json) {
    bool readCapability(String key) {
      final value = json[key];
      if (value == null) {
        return false;
      }
      if (value is! bool) {
        throw FormatException('invalid capability $key');
      }
      return value;
    }

    return UserCapabilities(
      canManageEmployees: readCapability('can_manage_employees'),
      canManageDepartments: readCapability('can_manage_departments'),
      canManagePositions: readCapability('can_manage_positions'),
      canViewAudit: readCapability('can_view_audit'),
      canLogoutAll: readCapability('can_logout_all'),
    );
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('invalid $key');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String || value.isEmpty) {
    throw FormatException('invalid $key');
  }
  return value;
}
