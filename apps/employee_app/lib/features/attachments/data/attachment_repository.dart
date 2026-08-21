import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'attachment.dart';

const attachmentAllowedExtensions = {
  'pdf',
  'docx',
  'xlsx',
  'jpg',
  'jpeg',
  'png',
};

final attachmentRepositoryProvider = Provider<AttachmentRepository>(
  (ref) => NetworkAttachmentRepository(ref.watch(apiClientProvider)),
);

abstract interface class AttachmentRepository {
  Future<AttachmentPage> fetchAttachments(
    String employeeId, {
    int page = 1,
    int pageSize = 20,
  });

  Future<EmployeeAttachment> uploadAttachment(
    String employeeId,
    AttachmentUploadCandidate candidate,
  );

  Future<ApiFileDownload> downloadAttachment(
    String attachmentId, {
    required String fileType,
  });

  Future<void> deleteAttachment(String attachmentId);
}

class NetworkAttachmentRepository implements AttachmentRepository {
  const NetworkAttachmentRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<AttachmentPage> fetchAttachments(
    String employeeId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      return AttachmentPage.fromJson(
        await _apiClient.getMap(
          ApiEndpoints.employeeAttachments(employeeId),
          queryParameters: {'page': page, 'page_size': pageSize},
        ),
      );
    } on AppException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const Failure.data();
    }
  }

  @override
  Future<EmployeeAttachment> uploadAttachment(
    String employeeId,
    AttachmentUploadCandidate candidate,
  ) async {
    try {
      final data = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          candidate.path,
          filename: candidate.name,
        ),
      });
      return EmployeeAttachment.fromJson(
        await _apiClient.postMap(
          ApiEndpoints.employeeAttachments(employeeId),
          data: data,
        ),
      );
    } on AppException catch (error) {
      throw _failureFor(error, operation: _AttachmentOperation.upload);
    } on FormatException {
      throw const Failure.data();
    } on FileSystemException {
      throw const Failure.validation('无法读取所选附件，请重新选择。');
    }
  }

  @override
  Future<ApiFileDownload> downloadAttachment(
    String attachmentId, {
    required String fileType,
  }) async {
    try {
      final fallbackFilename = switch (fileType.toLowerCase()) {
        'pdf' => 'attachment.pdf',
        'docx' => 'attachment.docx',
        'xlsx' => 'attachment.xlsx',
        'jpg' => 'attachment.jpg',
        'png' => 'attachment.png',
        _ => throw const Failure.data(),
      };
      return await _apiClient.downloadFile(
        ApiEndpoints.attachmentDownload(attachmentId),
        fallbackFilename: fallbackFilename,
        allowedExtensions: attachmentAllowedExtensions,
      );
    } on AppException catch (error) {
      throw _failureFor(error, operation: _AttachmentOperation.download);
    }
  }

  @override
  Future<void> deleteAttachment(String attachmentId) async {
    try {
      await _apiClient.deleteVoid(ApiEndpoints.attachment(attachmentId));
    } on AppException catch (error) {
      throw _failureFor(error, operation: _AttachmentOperation.delete);
    }
  }

  Failure _failureFor(AppException error, {_AttachmentOperation? operation}) {
    return switch (error.type) {
      AppExceptionType.network => const Failure.network(),
      AppExceptionType.unauthorized => const Failure.authentication(),
      AppExceptionType.forbidden => const Failure.permission(),
      AppExceptionType.validation
          when error.message == 'attachment_type_not_allowed' =>
        const Failure.validation(
          '不支持该附件类型，请选择 PDF、DOCX、XLSX、JPG、JPEG 或 PNG 文件。',
        ),
      AppExceptionType.validation
          when error.message == 'attachment_too_large' =>
        const Failure.validation('附件大小不能超过 10 MiB。'),
      AppExceptionType.validation
          when error.message == 'attachment_invalid_content' =>
        const Failure.validation('附件内容无效或与文件类型不匹配，请重新选择。'),
      AppExceptionType.validation
          when error.message == 'attachment_file_missing' &&
              operation == _AttachmentOperation.upload =>
        const Failure.validation('请选择要上传的附件。'),
      AppExceptionType.validation
          when error.message == 'attachment_file_missing' =>
        const Failure.validation('附件文件不存在，请重新加载后再试。'),
      AppExceptionType.validation
          when error.message == 'attachment_storage_conflict' =>
        const Failure.conflict('附件暂时无法保存，请重试。'),
      AppExceptionType.validation => const Failure.validation(),
      AppExceptionType.conflict
          when error.message == 'attachment_storage_conflict' =>
        const Failure.conflict('附件暂时无法保存，请重试。'),
      AppExceptionType.conflict => const Failure.conflict(),
      AppExceptionType.protocol => const Failure.service(),
      AppExceptionType.unexpected => const Failure(
        type: FailureType.unexpected,
        message: '附件操作失败，请稍后重试。',
      ),
    };
  }
}

enum _AttachmentOperation { upload, download, delete }
