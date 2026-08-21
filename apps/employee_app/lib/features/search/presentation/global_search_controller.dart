import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/global_search_repository.dart';

final globalSearchControllerProvider =
    AsyncNotifierProvider<GlobalSearchController, GlobalSearchPageData?>(
      GlobalSearchController.new,
      retry: (retryCount, error) => null,
    );

class GlobalSearchController extends AsyncNotifier<GlobalSearchPageData?> {
  String _lastQuery = '';

  @override
  Future<GlobalSearchPageData?> build() async => null;

  Future<void> search(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      state = const AsyncData(null);
      return;
    }
    _lastQuery = normalized;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(globalSearchRepositoryProvider).search(normalized),
    );
  }

  Future<void> retry() => search(_lastQuery);
}
