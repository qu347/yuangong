import 'employee.dart';

class EmployeePage {
  const EmployeePage({
    required this.count,
    required this.next,
    required this.previous,
    required this.results,
  });

  final int count;
  final String? next;
  final String? previous;
  final List<Employee> results;

  bool get hasNext => next != null;
  bool get hasPrevious => previous != null;

  factory EmployeePage.fromJson(Map<String, dynamic> json) {
    final count = json['count'];
    final next = json['next'];
    final previous = json['previous'];
    final results = json['results'];
    if (count is! int ||
        (next != null && next is! String) ||
        (previous != null && previous is! String) ||
        results is! List) {
      throw const FormatException('invalid employee page');
    }
    return EmployeePage(
      count: count,
      next: next as String?,
      previous: previous as String?,
      results: List<Employee>.unmodifiable(
        results.map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('invalid employee item');
          }
          return Employee.fromJson(item);
        }),
      ),
    );
  }
}
