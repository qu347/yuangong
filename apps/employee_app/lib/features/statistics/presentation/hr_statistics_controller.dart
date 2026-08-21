import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/hr_statistics_repository.dart';

final hrStatisticsControllerProvider =
    AsyncNotifierProvider<HrStatisticsController, HrStatistics>(
      HrStatisticsController.new,
      retry: (retryCount, error) => null,
    );

class HrStatisticsController extends AsyncNotifier<HrStatistics> {
  @override
  Future<HrStatistics> build() {
    return ref.watch(hrStatisticsRepositoryProvider).fetchStatistics();
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      ref.read(hrStatisticsRepositoryProvider).fetchStatistics,
    );
  }
}
