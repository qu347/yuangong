import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/department.dart';
import '../data/department_repository.dart';
import 'department_controller.dart';

final departmentManagementControllerProvider =
    Provider<DepartmentManagementController>(
      DepartmentManagementController.new,
    );

class DepartmentManagementController {
  DepartmentManagementController(this._ref);

  final Ref _ref;

  DepartmentRepository get _repository =>
      _ref.read(departmentRepositoryProvider);

  Future<Department> create(Map<String, dynamic> data) async {
    final result = await _repository.createDepartment(data);
    _ref.invalidate(departmentControllerProvider);
    return result;
  }

  Future<Department> update(String id, Map<String, dynamic> data) async {
    final result = await _repository.updateDepartment(id, data);
    _ref.invalidate(departmentControllerProvider);
    return result;
  }

  Future<DepartmentActionResult> setActive(
    String id, {
    required bool active,
  }) async {
    final result = active
        ? await _repository.activateDepartment(id)
        : await _repository.deactivateDepartment(id);
    _ref.invalidate(departmentControllerProvider);
    return result;
  }
}
