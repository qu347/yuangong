import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/health_repository.dart';
import '../data/health_response.dart';

final healthRepositoryProvider = Provider<HealthRepository>(
  (ref) => HealthRepository(ref.watch(apiClientProvider)),
);

final healthControllerProvider = FutureProvider<HealthResponse>(
  (ref) => ref.watch(healthRepositoryProvider).fetchHealth(),
  retry: (retryCount, error) => null,
);
