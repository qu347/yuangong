import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../data/attachment.dart';
import '../data/attachment_repository.dart';
import '../platform/attachment_file_picker.dart';
import 'attachment_controller.dart';

final attachmentUploadControllerProvider = AsyncNotifierProvider.autoDispose
    .family<AttachmentUploadController, AttachmentUploadState, String>(
      AttachmentUploadController.new,
      retry: (retryCount, error) => null,
    );

class AttachmentUploadState {
  const AttachmentUploadState({
    this.candidate,
    this.isChoosing = false,
    this.isUploading = false,
    this.failure,
  });

  final AttachmentUploadCandidate? candidate;
  final bool isChoosing;
  final bool isUploading;
  final Failure? failure;

  AttachmentUploadState copyWith({
    AttachmentUploadCandidate? candidate,
    bool clearCandidate = false,
    bool? isChoosing,
    bool? isUploading,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return AttachmentUploadState(
      candidate: clearCandidate ? null : candidate ?? this.candidate,
      isChoosing: isChoosing ?? this.isChoosing,
      isUploading: isUploading ?? this.isUploading,
      failure: clearFailure ? null : failure ?? this.failure,
    );
  }
}

class AttachmentUploadController extends AsyncNotifier<AttachmentUploadState> {
  AttachmentUploadController(this.employeeId);

  final String employeeId;
  var _selectionGeneration = 0;

  AttachmentRepository get _repository =>
      ref.read(attachmentRepositoryProvider);
  AttachmentFilePicker get _picker => ref.read(attachmentFilePickerProvider);

  @override
  Future<AttachmentUploadState> build() async => const AttachmentUploadState();

  Future<bool> chooseFile() async {
    final current = state.value ?? const AttachmentUploadState();
    final generation = ++_selectionGeneration;
    state = AsyncData(current.copyWith(isChoosing: true, clearFailure: true));
    try {
      final candidate = await _picker.pick();
      if (!ref.mounted || generation != _selectionGeneration) {
        return false;
      }
      if (candidate == null) {
        state = AsyncData(
          current.copyWith(isChoosing: false, clearFailure: true),
        );
        return false;
      }
      _validateCandidate(candidate);
      state = AsyncData(
        (state.value ?? current).copyWith(
          candidate: candidate,
          isChoosing: false,
          clearFailure: true,
        ),
      );
      return true;
    } on Failure catch (failure) {
      if (!ref.mounted || generation != _selectionGeneration) {
        return false;
      }
      state = AsyncData(
        current.copyWith(
          clearCandidate: true,
          isChoosing: false,
          failure: failure,
        ),
      );
      return false;
    } on Object {
      if (!ref.mounted || generation != _selectionGeneration) {
        return false;
      }
      state = AsyncData(
        current.copyWith(
          clearCandidate: true,
          isChoosing: false,
          failure: const Failure(
            type: FailureType.unexpected,
            message: '附件选择失败，请稍后重试。',
          ),
        ),
      );
      return false;
    }
  }

  Future<bool> submit() async {
    final current = state.value ?? const AttachmentUploadState();
    if (current.isUploading) {
      throw StateError('Attachment upload is already in progress.');
    }
    if (current.isChoosing) {
      throw StateError('Attachment selection is still in progress.');
    }
    final candidate = current.candidate;
    if (candidate == null) {
      state = AsyncData(
        current.copyWith(failure: const Failure.validation('请选择要上传的附件。')),
      );
      return false;
    }

    final keepAliveLink = ref.keepAlive();
    state = AsyncData(current.copyWith(isUploading: true, clearFailure: true));
    Failure? caughtFailure;
    var uploaded = false;
    try {
      final attachment = await _repository.uploadAttachment(
        employeeId,
        candidate,
      );
      uploaded = true;
      if (ref.mounted) {
        final listProvider = attachmentControllerProvider(employeeId);
        if (ref.exists(listProvider)) {
          await ref.read(listProvider.notifier).refreshAfterUpload(attachment);
        } else {
          ref.invalidate(listProvider);
        }
      }
      return true;
    } on Failure catch (failure) {
      caughtFailure = failure;
      return false;
    } on Object {
      caughtFailure = const Failure(
        type: FailureType.unexpected,
        message: '附件上传失败，请稍后重试。',
      );
      return false;
    } finally {
      try {
        if (ref.mounted) {
          final latest = state.value ?? current;
          state = AsyncData(
            latest.copyWith(
              isUploading: false,
              clearCandidate: uploaded,
              failure: caughtFailure,
              clearFailure: uploaded,
            ),
          );
        }
      } finally {
        keepAliveLink.close();
      }
    }
  }

  void _validateCandidate(AttachmentUploadCandidate candidate) {
    final extension = candidate.extension.toLowerCase();
    if (!attachmentAllowedExtensions.contains(extension)) {
      throw const Failure.validation(
        '不支持该附件类型，请选择 PDF、DOCX、XLSX、JPG、JPEG 或 PNG 文件。',
      );
    }
    if (candidate.size <= 0) {
      throw const Failure.validation('附件内容不能为空。');
    }
    if (candidate.size > attachmentMaxBytes) {
      throw const Failure.validation('附件大小不能超过 10 MiB。');
    }
  }
}
