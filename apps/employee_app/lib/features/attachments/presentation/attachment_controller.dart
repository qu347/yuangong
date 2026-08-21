import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../data/attachment.dart';
import '../data/attachment_repository.dart';
import '../platform/attachment_file_saver.dart';

final attachmentControllerProvider = AsyncNotifierProvider.autoDispose
    .family<AttachmentController, AttachmentState, String>(
      AttachmentController.new,
      retry: (retryCount, error) => null,
    );

class AttachmentState {
  AttachmentState({
    required List<EmployeeAttachment> items,
    required this.count,
    required this.page,
    required this.hasNext,
    this.isLoadingMore = false,
    Set<String> deletingIds = const {},
  }) : items = List.unmodifiable(items),
       deletingIds = Set.unmodifiable(deletingIds);

  final List<EmployeeAttachment> items;
  final int count;
  final int page;
  final bool hasNext;
  final bool isLoadingMore;
  final Set<String> deletingIds;

  AttachmentState copyWith({
    List<EmployeeAttachment>? items,
    int? count,
    int? page,
    bool? hasNext,
    bool? isLoadingMore,
    Set<String>? deletingIds,
  }) {
    return AttachmentState(
      items: items ?? this.items,
      count: count ?? this.count,
      page: page ?? this.page,
      hasNext: hasNext ?? this.hasNext,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      deletingIds: deletingIds ?? this.deletingIds,
    );
  }
}

class AttachmentController extends AsyncNotifier<AttachmentState> {
  AttachmentController(this.employeeId);

  final String employeeId;
  var _refreshGeneration = 0;

  AttachmentRepository get _repository =>
      ref.read(attachmentRepositoryProvider);
  AttachmentFileSaver get _saver => ref.read(attachmentFileSaverProvider);

  @override
  Future<AttachmentState> build() => _load();

  Future<AttachmentState> _load() async {
    final page = await _repository.fetchAttachments(employeeId);
    return AttachmentState(
      items: _mergeAttachments(const [], page.results),
      count: page.count,
      page: 1,
      hasNext: page.hasNext,
    );
  }

  Future<void> retry() async {
    _refreshGeneration += 1;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(_load);
    if (ref.mounted) {
      state = result;
    }
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null) {
      throw StateError('Attachments are not ready.');
    }
    if (current.isLoadingMore) {
      throw StateError('Attachment page loading is already in progress.');
    }
    if (!current.hasNext) {
      return;
    }

    final generation = _refreshGeneration;
    final nextPage = current.page + 1;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final response = await _repository.fetchAttachments(
        employeeId,
        page: nextPage,
      );
      if (!ref.mounted || generation != _refreshGeneration) {
        return;
      }
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          items: _mergeAttachments(latest.items, response.results),
          count: response.count,
          page: nextPage,
          hasNext: response.hasNext,
          isLoadingMore: false,
        ),
      );
    } on Failure {
      rethrow;
    } on Object {
      throw const Failure(
        type: FailureType.unexpected,
        message: '员工附件加载失败，请稍后重试。',
      );
    } finally {
      if (ref.mounted && generation == _refreshGeneration) {
        final latest = state.value;
        if (latest != null && latest.isLoadingMore) {
          state = AsyncData(latest.copyWith(isLoadingMore: false));
        }
      }
    }
  }

  Future<void> refreshAfterUpload(EmployeeAttachment uploaded) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final generation = ++_refreshGeneration;
    final alreadyLoaded = current.items.any((item) => item.id == uploaded.id);
    final optimistic = current.copyWith(
      items: _mergeAttachments(current.items, [uploaded]),
      count: alreadyLoaded ? current.count : current.count + 1,
      isLoadingMore: false,
    );
    state = AsyncData(optimistic);

    try {
      final refreshed = await _loadThroughPage(current.page);
      if (!ref.mounted || generation != _refreshGeneration) {
        return;
      }
      final latest = state.value ?? optimistic;
      final merged = _mergeAttachments(optimistic.items, refreshed.items);
      state = AsyncData(
        refreshed.copyWith(
          items: merged,
          count: refreshed.count < merged.length
              ? merged.length
              : refreshed.count,
          deletingIds: latest.deletingIds,
        ),
      );
    } on Object {
      // Upload already succeeded. Keep the optimistic, de-duplicated snapshot
      // and let the next explicit refresh reconcile server pagination.
    }
  }

  Future<AttachmentSaveResult> download(EmployeeAttachment attachment) async {
    final repository = _repository;
    final saver = _saver;
    final file = await repository.downloadAttachment(
      attachment.id,
      fileType: attachment.fileType,
    );
    return saver.save(file.bytes, file.filename, file.mimeType);
  }

  Future<void> delete(String attachmentId) async {
    final current = state.value;
    if (current == null) {
      throw StateError('Attachments are not ready.');
    }
    if (current.deletingIds.contains(attachmentId)) {
      throw StateError('Attachment deletion is already in progress.');
    }

    state = AsyncData(
      current.copyWith(deletingIds: {...current.deletingIds, attachmentId}),
    );
    var deleted = false;
    try {
      await _repository.deleteAttachment(attachmentId);
      if (!ref.mounted) {
        return;
      }
      deleted = true;
      final refreshGeneration = ++_refreshGeneration;
      final beforeRefresh = state.value ?? current;
      final optimistic = beforeRefresh.copyWith(
        items: beforeRefresh.items
            .where((item) => item.id != attachmentId)
            .toList(),
        count: beforeRefresh.count > 0 ? beforeRefresh.count - 1 : 0,
        isLoadingMore: false,
      );
      state = AsyncData(optimistic);
      try {
        final refreshed = await _loadThroughPage(beforeRefresh.page);
        if (!ref.mounted) {
          return;
        }
        if (refreshGeneration == _refreshGeneration) {
          final latest = state.value ?? optimistic;
          state = AsyncData(
            refreshed.copyWith(
              items: refreshed.items
                  .where((item) => item.id != attachmentId)
                  .toList(),
              deletingIds: latest.deletingIds,
            ),
          );
        }
      } on Object {
        // The delete is authoritative. Keep the optimistic removal if the
        // follow-up list refresh is temporarily unavailable.
      }
    } on Failure {
      rethrow;
    } on Object {
      throw const Failure(
        type: FailureType.unexpected,
        message: '附件删除失败，请稍后重试。',
      );
    } finally {
      final latest = ref.mounted ? state.value : null;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(
            items: deleted
                ? latest.items.where((item) => item.id != attachmentId).toList()
                : latest.items,
            deletingIds: {...latest.deletingIds}..remove(attachmentId),
          ),
        );
      }
    }
  }

  Future<AttachmentState> _loadThroughPage(int targetPage) async {
    var requestedPage = 1;
    var merged = <EmployeeAttachment>[];
    AttachmentPage? response;
    do {
      response = await _repository.fetchAttachments(
        employeeId,
        page: requestedPage,
      );
      merged = _mergeAttachments(merged, response.results);
      if (!response.hasNext || requestedPage >= targetPage) {
        break;
      }
      requestedPage += 1;
    } while (true);

    return AttachmentState(
      items: merged,
      count: response.count,
      page: requestedPage,
      hasNext: response.hasNext,
    );
  }
}

List<EmployeeAttachment> _mergeAttachments(
  Iterable<EmployeeAttachment> existing,
  Iterable<EmployeeAttachment> incoming,
) {
  final byId = <String, EmployeeAttachment>{};
  for (final attachment in existing) {
    byId[attachment.id] = attachment;
  }
  for (final attachment in incoming) {
    byId[attachment.id] = attachment;
  }
  final merged = byId.values.toList()
    ..sort((first, second) {
      final createdAtOrder = second.createdAt.compareTo(first.createdAt);
      return createdAtOrder != 0
          ? createdAtOrder
          : second.id.compareTo(first.id);
    });
  return merged;
}
