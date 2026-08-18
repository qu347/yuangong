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

  bool get isActive => employmentStatus == 'active';

  factory Employee.fromJson(Map<String, dynamic> json) {
    final departmentJson = json['department'];
    final positionJson = json['position'];
    final hireDateJson = json['hire_date'];
    if (departmentJson is! Map<String, dynamic>) {
      throw const FormatException('invalid employee department');
    }
    if (positionJson != null && positionJson is! Map<String, dynamic>) {
      throw const FormatException('invalid employee position');
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
