class PositionDepartment {
  const PositionDepartment({
    required this.id,
    required this.code,
    required this.name,
  });

  final String id;
  final String code;
  final String name;

  factory PositionDepartment.fromJson(Map<String, dynamic> json) {
    return PositionDepartment(
      id: _requiredString(json, 'id'),
      code: _requiredString(json, 'code'),
      name: _requiredString(json, 'name'),
    );
  }
}

class Position {
  const Position({
    required this.id,
    required this.code,
    required this.name,
    required this.department,
    required this.status,
  });

  final String id;
  final String code;
  final String name;
  final PositionDepartment department;
  final String status;

  bool get isActive => status == 'active';

  factory Position.fromJson(Map<String, dynamic> json) {
    final departmentJson = json['department'];
    if (departmentJson is! Map<String, dynamic>) {
      throw const FormatException('invalid position department');
    }
    return Position(
      id: _requiredString(json, 'id'),
      code: _requiredString(json, 'code'),
      name: _requiredString(json, 'name'),
      department: PositionDepartment.fromJson(departmentJson),
      status: _requiredString(json, 'status'),
    );
  }
}

class PositionActionResult {
  const PositionActionResult({required this.position, required this.changed});

  final Position position;
  final bool changed;

  factory PositionActionResult.fromJson(Map<String, dynamic> json) {
    final positionJson = json['position'];
    final changed = json['changed'];
    if (positionJson is! Map<String, dynamic> || changed is! bool) {
      throw const FormatException('invalid position action result');
    }
    return PositionActionResult(
      position: Position.fromJson(positionJson),
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
