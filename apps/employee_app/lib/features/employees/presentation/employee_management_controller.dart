import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../departments/presentation/department_controller.dart';
import '../data/employee.dart';
import '../data/employee_repository.dart';
import 'employee_directory_controller.dart';

final employeeManagementControllerProvider =
    Provider<EmployeeManagementController>(EmployeeManagementController.new);

final employeeDetailProvider = FutureProvider.family<Employee, String>(
  (ref, id) => ref.watch(employeeRepositoryProvider).fetchEmployee(id),
  retry: (retryCount, error) => null,
);

class EmployeeManagementController {
  EmployeeManagementController(this._ref);

  final Ref _ref;

  EmployeeRepository get _repository => _ref.read(employeeRepositoryProvider);

  Future<Employee> load(String id) => _repository.fetchEmployee(id);

  Future<Employee> create(Map<String, dynamic> data) async {
    final employee = await _repository.createEmployee(data);
    _refreshDirectory();
    return employee;
  }

  Future<Employee> update(String id, Map<String, dynamic> data) async {
    final employee = await _repository.updateEmployee(id, data);
    _refreshDirectory();
    _ref.invalidate(employeeDetailProvider(id));
    return employee;
  }

  Future<EmployeeActionResult> depart(String id) async {
    final result = await _repository.departEmployee(id);
    _refreshDirectory();
    _ref.invalidate(employeeDetailProvider(id));
    return result;
  }

  Future<EmployeeActionResult> reactivate(String id) async {
    final result = await _repository.reactivateEmployee(id);
    _refreshDirectory();
    _ref.invalidate(employeeDetailProvider(id));
    return result;
  }

  void _refreshDirectory() {
    _ref.invalidate(employeeDirectoryControllerProvider);
    _ref.invalidate(departmentControllerProvider);
  }
}
