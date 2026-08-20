import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dashboard_repository.dart';
import '../data/dashboard_summary.dart';

final dashboardControllerProvider =
    AsyncNotifierProvider<DashboardController, DashboardSummary>(
      DashboardController.new,
      retry: (retryCount, error) => null,
    );

class DashboardController extends AsyncNotifier<DashboardSummary> {
  @override
  Future<DashboardSummary> build() {
    return ref.watch(dashboardRepositoryProvider).fetchSummary();
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      ref.read(dashboardRepositoryProvider).fetchSummary,
    );
  }
}
