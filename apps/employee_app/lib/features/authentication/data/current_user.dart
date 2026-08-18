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
  });

  final String id;
  final String username;
  final String displayName;
  final String? employeeId;
  final String? employeeNo;
  final CurrentUserDepartment? department;
  final List<String> roles;

  factory CurrentUser.fromJson(Map<String, dynamic> json) {
    final departmentJson = json['department'];
    final rolesJson = json['roles'];
    if (departmentJson != null && departmentJson is! Map<String, dynamic>) {
      throw const FormatException('invalid current user department');
    }
    if (rolesJson is! List || rolesJson.any((role) => role is! String)) {
      throw const FormatException('invalid current user roles');
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
