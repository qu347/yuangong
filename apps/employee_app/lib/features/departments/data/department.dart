class Department {
  const Department({
    required this.id,
    required this.code,
    required this.name,
    required this.parentId,
    required this.status,
    required this.sortOrder,
  });

  final String id;
  final String code;
  final String name;
  final String? parentId;
  final String status;
  final int sortOrder;

  bool get isActive => status == 'active';

  factory Department.fromJson(Map<String, dynamic> json) {
    final parentId = json['parent'];
    final sortOrder = json['sort_order'];
    if (parentId != null && parentId is! String) {
      throw const FormatException('invalid department parent');
    }
    if (sortOrder is! int) {
      throw const FormatException('invalid department sort order');
    }
    return Department(
      id: _requiredString(json, 'id'),
      code: _requiredString(json, 'code'),
      name: _requiredString(json, 'name'),
      parentId: parentId as String?,
      status: _requiredString(json, 'status'),
      sortOrder: sortOrder,
    );
  }
}

class DepartmentActionResult {
  const DepartmentActionResult({
    required this.department,
    required this.changed,
  });

  final Department department;
  final bool changed;

  factory DepartmentActionResult.fromJson(Map<String, dynamic> json) {
    final departmentJson = json['department'];
    final changed = json['changed'];
    if (departmentJson is! Map<String, dynamic> || changed is! bool) {
      throw const FormatException('invalid department action result');
    }
    return DepartmentActionResult(
      department: Department.fromJson(departmentJson),
      changed: changed,
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
