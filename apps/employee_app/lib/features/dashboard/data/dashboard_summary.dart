class RecentOperation {
  const RecentOperation({
    required this.action,
    required this.resourceType,
    required this.resourceLabel,
    required this.createdAt,
  });

  final String action;
  final String resourceType;
  final String resourceLabel;
  final DateTime createdAt;

  factory RecentOperation.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(_requiredString(json, 'created_at'));
    if (createdAt == null) {
      throw const FormatException('invalid recent operation date');
    }
    return RecentOperation(
      action: _requiredString(json, 'action'),
      resourceType: _requiredString(json, 'resource_type'),
      resourceLabel: _string(json, 'resource_label'),
      createdAt: createdAt,
    );
  }
}

class DashboardSummary {
  const DashboardSummary({
    required this.employeeTotal,
    required this.activeEmployee,
    required this.departedEmployee,
    required this.departmentTotal,
    required this.positionTotal,
    required this.recentOperations,
  });

  final int employeeTotal;
  final int activeEmployee;
  final int departedEmployee;
  final int departmentTotal;
  final int positionTotal;
  final List<RecentOperation> recentOperations;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final operations = json['recent_operations'];
    if (operations is! List) {
      throw const FormatException('invalid recent operations');
    }
    return DashboardSummary(
      employeeTotal: _integer(json, 'employee_total'),
      activeEmployee: _integer(json, 'active_employee'),
      departedEmployee: _integer(json, 'departed_employee'),
      departmentTotal: _integer(json, 'department_total'),
      positionTotal: _integer(json, 'position_total'),
      recentOperations: List.unmodifiable(
        operations.map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('invalid recent operation');
          }
          return RecentOperation.fromJson(item);
        }),
      ),
    );
  }
}

int _integer(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('invalid $key');
  return value;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) throw FormatException('invalid $key');
  return value;
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('invalid $key');
  return value;
}
