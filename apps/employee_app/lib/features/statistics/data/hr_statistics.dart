class DepartmentHeadcount {
  const DepartmentHeadcount({
    required this.id,
    required this.name,
    required this.count,
  });

  final String id;
  final String name;
  final int count;

  factory DepartmentHeadcount.fromJson(Map<String, dynamic> json) {
    return DepartmentHeadcount(
      id: _requiredString(json, 'department_id'),
      name: _requiredString(json, 'department_name'),
      count: _requiredInt(json, 'count'),
    );
  }
}

class HireTrendPoint {
  const HireTrendPoint({required this.month, required this.count});

  final String month;
  final int count;

  factory HireTrendPoint.fromJson(Map<String, dynamic> json) {
    return HireTrendPoint(
      month: _requiredString(json, 'month'),
      count: _requiredInt(json, 'count'),
    );
  }
}

class StatisticsCount {
  const StatisticsCount({required this.label, required this.count});

  final String label;
  final int count;

  factory StatisticsCount.fromJson(Map<String, dynamic> json) {
    return StatisticsCount(
      label: _requiredString(json, 'label'),
      count: _requiredInt(json, 'count'),
    );
  }
}

class HrStatistics {
  const HrStatistics({
    required this.employeeTotal,
    required this.positionTotal,
    required this.departmentHeadcount,
    required this.hireTrend,
    required this.genderDistribution,
    required this.ageDistribution,
  });

  final int employeeTotal;
  final int positionTotal;
  final List<DepartmentHeadcount> departmentHeadcount;
  final List<HireTrendPoint> hireTrend;
  final List<StatisticsCount> genderDistribution;
  final List<StatisticsCount> ageDistribution;

  factory HrStatistics.fromJson(Map<String, dynamic> json) {
    return HrStatistics(
      employeeTotal: _requiredInt(json, 'employee_total'),
      positionTotal: _requiredInt(json, 'position_total'),
      departmentHeadcount: _parseList(
        json,
        'department_headcount',
        DepartmentHeadcount.fromJson,
      ),
      hireTrend: _parseList(json, 'hire_trend', HireTrendPoint.fromJson),
      genderDistribution: _parseList(
        json,
        'gender_distribution',
        StatisticsCount.fromJson,
      ),
      ageDistribution: _parseList(
        json,
        'age_distribution',
        StatisticsCount.fromJson,
      ),
    );
  }
}

List<T> _parseList<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic>) parse,
) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('invalid $key');
  }
  return List<T>.unmodifiable(
    value.map((item) {
      if (item is! Map<String, dynamic>) {
        throw FormatException('invalid $key item');
      }
      return parse(item);
    }),
  );
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('invalid $key');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw FormatException('invalid $key');
  }
  return value;
}
