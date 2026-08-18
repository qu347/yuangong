import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/position.dart';
import '../data/position_repository.dart';

final positionListProvider = FutureProvider.autoDispose<List<Position>>(
  (ref) => ref.watch(positionRepositoryProvider).fetchPositions(),
  retry: (retryCount, error) => null,
);

final positionManagementControllerProvider =
    Provider<PositionManagementController>(PositionManagementController.new);

class PositionManagementController {
  PositionManagementController(this._ref);

  final Ref _ref;

  PositionRepository get _repository => _ref.read(positionRepositoryProvider);

  Future<Position> create(Map<String, dynamic> data) async {
    final result = await _repository.createPosition(data);
    _ref.invalidate(positionListProvider);
    return result;
  }

  Future<Position> update(String id, Map<String, dynamic> data) async {
    final result = await _repository.updatePosition(id, data);
    _ref.invalidate(positionListProvider);
    return result;
  }

  Future<PositionActionResult> setActive(
    String id, {
    required bool active,
  }) async {
    final result = active
        ? await _repository.activatePosition(id)
        : await _repository.deactivatePosition(id);
    _ref.invalidate(positionListProvider);
    return result;
  }
}
