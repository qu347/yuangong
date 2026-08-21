class DirectoryReference {
  const DirectoryReference({
    required this.id,
    required this.code,
    required this.name,
  });

  final String id;
  final String code;
  final String name;

  factory DirectoryReference.fromJson(Map<String, dynamic> json) {
    return DirectoryReference(
      id: _requiredString(json, 'id'),
      code: _requiredString(json, 'code'),
      name: _requiredString(json, 'name'),
    );
  }
}

class EmployeeReference {
  const EmployeeReference({
    required this.id,
    required this.employeeNo,
    required this.fullName,
  });

  final String id;
  final String employeeNo;
  final String fullName;

  factory EmployeeReference.fromJson(Map<String, dynamic> json) {
    return EmployeeReference(
      id: _requiredString(json, 'id'),
      employeeNo: _requiredString(json, 'employee_no'),
      fullName: _requiredString(json, 'full_name'),
    );
  }
}

class Employee {
  const Employee({
    required this.id,
    required this.employeeNo,
    required this.fullName,
    required this.workEmail,
    required this.workPhone,
    required this.department,
    required this.position,
    required this.employmentStatus,
    required this.hireDate,
    this.avatarUrl = '',
    this.gender = 'unspecified',
    this.birthday,
    this.officeLocation = '',
    this.manager,
    this.description = '',
    this.updatedAt,
  });

  final String id;
  final String employeeNo;
  final String fullName;
  final String workEmail;
  final String workPhone;
  final DirectoryReference department;
  final DirectoryReference? position;
  final String employmentStatus;
  final DateTime? hireDate;
  final String avatarUrl;
  final String gender;
  final DateTime? birthday;
  final String officeLocation;
  final EmployeeReference? manager;
  final String description;
  final DateTime? updatedAt;

  bool get isActive => employmentStatus == 'active';

  factory Employee.fromJson(Map<String, dynamic> json) {
    final departmentJson = json['department'];
    final positionJson = json['position'];
    final hireDateJson = json['hire_date'];
    final updatedAtJson = json['updated_at'];
    final birthdayJson = json['birthday'];
    final managerJson = json['manager'];
    if (departmentJson is! Map<String, dynamic>) {
      throw const FormatException('invalid employee department');
    }
    if (positionJson != null && positionJson is! Map<String, dynamic>) {
      throw const FormatException('invalid employee position');
    }
    if (managerJson != null && managerJson is! Map<String, dynamic>) {
      throw const FormatException('invalid employee manager');
    }
    DateTime? hireDate;
    if (hireDateJson != null) {
      if (hireDateJson is! String) {
        throw const FormatException('invalid employee hire date');
      }
      hireDate = DateTime.tryParse(hireDateJson);
      if (hireDate == null) {
        throw const FormatException('invalid employee hire date');
      }
    }
    DateTime? updatedAt;
    if (updatedAtJson != null) {
      if (updatedAtJson is! String) {
        throw const FormatException('invalid employee updated at');
      }
      updatedAt = DateTime.tryParse(updatedAtJson);
      if (updatedAt == null) {
        throw const FormatException('invalid employee updated at');
      }
    }
    DateTime? birthday;
    if (birthdayJson != null) {
      if (birthdayJson is! String ||
          (birthday = DateTime.tryParse(birthdayJson)) == null) {
        throw const FormatException('invalid employee birthday');
      }
    }
    return Employee(
      id: _requiredString(json, 'id'),
      employeeNo: _requiredString(json, 'employee_no'),
      fullName: _requiredString(json, 'full_name'),
      workEmail: _string(json, 'work_email'),
      workPhone: _string(json, 'work_phone'),
      department: DirectoryReference.fromJson(departmentJson),
      position: positionJson == null
          ? null
          : DirectoryReference.fromJson(positionJson as Map<String, dynamic>),
      employmentStatus: _requiredString(json, 'employment_status'),
      hireDate: hireDate,
      avatarUrl: _optionalString(json, 'avatar_url'),
      gender: _optionalString(json, 'gender', fallback: 'unspecified'),
      birthday: birthday,
      officeLocation: _optionalString(json, 'office_location'),
      manager: managerJson == null
          ? null
          : EmployeeReference.fromJson(managerJson as Map<String, dynamic>),
      description: _optionalString(json, 'description'),
      updatedAt: updatedAt,
    );
  }
}

class EmployeeActionResult {
  const EmployeeActionResult({
    required this.employee,
    required this.changed,
    required this.accountRequiresActivation,
  });

  final Employee employee;
  final bool changed;
  final bool accountRequiresActivation;

  factory EmployeeActionResult.fromJson(Map<String, dynamic> json) {
    final employeeJson = json['employee'];
    final changed = json['changed'];
    final accountRequiresActivation = json['account_requires_activation'];
    if (employeeJson is! Map<String, dynamic> || changed is! bool) {
      throw const FormatException('invalid employee action result');
    }
    if (accountRequiresActivation != null &&
        accountRequiresActivation is! bool) {
      throw const FormatException('invalid account activation requirement');
    }
    return EmployeeActionResult(
      employee: Employee.fromJson(employeeJson),
      changed: changed,
      accountRequiresActivation: accountRequiresActivation == true,
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

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('invalid $key');
  }
  return value;
}

String _optionalString(
  Map<String, dynamic> json,
  String key, {
  String fallback = '',
}) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  if (value is! String) {
    throw FormatException('invalid $key');
  }
  return value;
}
