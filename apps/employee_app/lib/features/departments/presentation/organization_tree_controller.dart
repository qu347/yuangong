import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../employees/data/employee.dart';
import '../../employees/data/employee_repository.dart';
import '../data/organization_tree_repository.dart';

final departmentMembersProvider = FutureProvider.family<List<Employee>, String>(
  (ref, departmentId) async {
    final page = await ref
        .watch(employeeRepositoryProvider)
        .fetchEmployees(departmentId: departmentId, pageSize: 100);
    return page.results;
  },
  retry: (retryCount, error) => null,
);

final organizationTreeControllerProvider =
    AsyncNotifierProvider<
      OrganizationTreeController,
      List<OrganizationTreeNode>
    >(OrganizationTreeController.new, retry: (retryCount, error) => null);

class OrganizationTreeController
    extends AsyncNotifier<List<OrganizationTreeNode>> {
  @override
  Future<List<OrganizationTreeNode>> build() =>
      ref.watch(organizationTreeRepositoryProvider).fetchTree();

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      ref.read(organizationTreeRepositoryProvider).fetchTree,
    );
  }
}
