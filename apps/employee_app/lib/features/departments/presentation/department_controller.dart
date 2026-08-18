import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/department.dart';
import '../data/department_repository.dart';

final departmentControllerProvider =
    AsyncNotifierProvider<DepartmentController, List<Department>>(
      DepartmentController.new,
      retry: (retryCount, error) => null,
    );

class DepartmentController extends AsyncNotifier<List<Department>> {
  @override
  Future<List<Department>> build() {
    return ref.watch(departmentRepositoryProvider).fetchDepartments();
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      ref.read(departmentRepositoryProvider).fetchDepartments,
    );
  }
}
