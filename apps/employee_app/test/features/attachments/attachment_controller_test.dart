import 'dart:async';
import 'dart:typed_data';

import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/features/attachments/data/attachment.dart'
    as attachment_data;
import 'package:employee_app/features/attachments/data/attachment_repository.dart';
import 'package:employee_app/features/attachments/platform/attachment_file_picker.dart';
import 'package:employee_app/features/attachments/platform/attachment_file_saver.dart';
import 'package:employee_app/features/attachments/presentation/attachment_controller.dart';
import 'package:employee_app/features/attachments/presentation/attachment_upload_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const employeeId = '20000000-0000-0000-0000-000000000001';

final contractAttachment = attachment_data.EmployeeAttachment(
  id: '10000000-0000-0000-0000-000000000001',
  employeeId: employeeId,
  filename: '合同.pdf',
  fileType: 'pdf',
  fileSize: 1024,
  uploadedBy: const attachment_data.AttachmentUploader(
    id: '30000000-0000-0000-0000-000000000001',
    username: 'hr.manager',
  ),
  createdAt: DateTime.utc(2026, 8, 21, 9, 30),
);

final portraitAttachment = attachment_data.EmployeeAttachment(
  id: '10000000-0000-0000-0000-000000000002',
  employeeId: employeeId,
  filename: '证件照.png',
  fileType: 'png',
  fileSize: 2048,
  uploadedBy: null,
  createdAt: DateTime.utc(2026, 8, 21, 10),
);

attachment_data.AttachmentPage pageOf(
  List<attachment_data.EmployeeAttachment> items,
) => attachment_data.AttachmentPage(
  count: items.length,
  next: null,
  previous: null,
  results: items,
);

attachment_data.EmployeeAttachment attachmentAt(int sequence) =>
    attachment_data.EmployeeAttachment(
      id: '10000000-0000-0000-0000-${sequence.toString().padLeft(12, '0')}',
      employeeId: employeeId,
      filename: '附件-$sequence.pdf',
      fileType: 'pdf',
      fileSize: sequence,
      uploadedBy: null,
      createdAt: DateTime.utc(
        2026,
        8,
        22,
      ).subtract(Duration(minutes: sequence)),
    );

attachment_data.AttachmentPage pagedResponse({
  required int count,
  required int page,
  required List<attachment_data.EmployeeAttachment> results,
  required bool hasNext,
}) => attachment_data.AttachmentPage(
  count: count,
  next: hasNext
      ? 'https://api.example.test/attachments/?page=${page + 1}'
      : null,
  previous: page > 1
      ? 'https://api.example.test/attachments/?page=${page - 1}'
      : null,
  results: results,
);

class FakeAttachmentRepository implements AttachmentRepository {
  final fetchResponses = <Object>[];
  Object? uploadResponse;
  Object? downloadResponse;
  Completer<void>? deleteCompleter;
  final deleteCompleters = <String, Completer<void>>{};
  final missingDeleteIds = <String>{};
  var items = <attachment_data.EmployeeAttachment>[];
  var fetchCount = 0;
  final requestedPages = <int>[];

  @override
  Future<attachment_data.AttachmentPage> fetchAttachments(
    String employeeId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    fetchCount += 1;
    requestedPages.add(page);
    if (fetchResponses.isNotEmpty) {
      final response = fetchResponses.removeAt(0);
      if (response is attachment_data.AttachmentPage) {
        items = List.of(response.results);
        return response;
      }
      if (response is Future<attachment_data.AttachmentPage>) {
        final page = await response;
        items = List.of(page.results);
        return page;
      }
      throw response;
    }
    return pageOf(items);
  }

  @override
  Future<attachment_data.EmployeeAttachment> uploadAttachment(
    String employeeId,
    attachment_data.AttachmentUploadCandidate candidate,
  ) async {
    final response = uploadResponse;
    if (response is Future<attachment_data.EmployeeAttachment>) {
      final uploaded = await response;
      items = [...items, uploaded];
      return uploaded;
    }
    if (response is attachment_data.EmployeeAttachment) {
      items = [...items, response];
      return response;
    }
    if (response != null) {
      throw response;
    }
    items = [...items, contractAttachment];
    return contractAttachment;
  }

  @override
  Future<ApiFileDownload> downloadAttachment(
    String attachmentId, {
    required String fileType,
  }) async {
    final response = downloadResponse;
    if (response is Future<ApiFileDownload>) {
      return response;
    }
    if (response is ApiFileDownload) {
      return response;
    }
    if (response != null) {
      throw response;
    }
    return ApiFileDownload(
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: '合同.pdf',
      mimeType: 'application/pdf',
    );
  }

  @override
  Future<void> deleteAttachment(String attachmentId) async {
    if (missingDeleteIds.contains(attachmentId)) {
      throw const Failure.validation('附件文件不存在，请重新加载后再试。');
    }
    await (deleteCompleters[attachmentId] ?? deleteCompleter)?.future;
    items = items.where((item) => item.id != attachmentId).toList();
  }
}

class FakeAttachmentPicker implements AttachmentFilePicker {
  FakeAttachmentPicker(this.response);

  Object? response;

  @override
  Future<attachment_data.AttachmentUploadCandidate?> pick() async {
    final current = response;
    if (current is attachment_data.AttachmentUploadCandidate?) {
      return current;
    }
    if (current is Future<attachment_data.AttachmentUploadCandidate?>) {
      return current;
    }
    throw current;
  }
}

class QueuedAttachmentPicker implements AttachmentFilePicker {
  QueuedAttachmentPicker(this.responses);

  final List<Future<attachment_data.AttachmentUploadCandidate?>> responses;
  var index = 0;

  @override
  Future<attachment_data.AttachmentUploadCandidate?> pick() {
    return responses[index++];
  }
}

class FakeAttachmentSaver implements AttachmentFileSaver {
  FakeAttachmentSaver(this.result);

  AttachmentSaveResult result;

  @override
  Future<AttachmentSaveResult> save(
    Uint8List bytes,
    String filename,
    String mimeType,
  ) async => result;
}

ProviderContainer attachmentContainer({
  required FakeAttachmentRepository repository,
  AttachmentFilePicker? picker,
  AttachmentFileSaver? saver,
}) {
  final container = ProviderContainer(
    overrides: [
      attachmentRepositoryProvider.overrideWithValue(repository),
      if (picker != null)
        attachmentFilePickerProvider.overrideWithValue(picker),
      if (saver != null) attachmentFileSaverProvider.overrideWithValue(saver),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('attachment controller exposes loading then empty data', () async {
    final repository = FakeAttachmentRepository();
    final pending = Completer<attachment_data.AttachmentPage>();
    repository.fetchResponses.add(pending.future);
    final container = attachmentContainer(repository: repository);

    final future = container.read(
      attachmentControllerProvider(employeeId).future,
    );
    expect(
      container.read(attachmentControllerProvider(employeeId)).isLoading,
      isTrue,
    );

    pending.complete(pageOf(const []));
    expect((await future).items, isEmpty);
  });

  test('attachment controller retries a safe Failure', () async {
    final repository = FakeAttachmentRepository()
      ..fetchResponses.addAll([
        const Failure.network(),
        pageOf([contractAttachment]),
      ]);
    final container = attachmentContainer(repository: repository);

    await expectLater(
      container.read(attachmentControllerProvider(employeeId).future),
      throwsA(isA<Failure>()),
    );
    await container
        .read(attachmentControllerProvider(employeeId).notifier)
        .retry();

    expect(
      container.read(attachmentControllerProvider(employeeId)).value?.items,
      [contractAttachment],
    );
    expect(repository.fetchCount, 2);
  });

  test(
    'loads page two with deterministic de-duplication and ordering',
    () async {
      final firstTwenty = List.generate(20, (index) => attachmentAt(index + 1));
      final twentyFirst = attachmentAt(21);
      final repository = FakeAttachmentRepository()
        ..fetchResponses.addAll([
          pagedResponse(
            count: 21,
            page: 1,
            results: firstTwenty,
            hasNext: true,
          ),
          pagedResponse(
            count: 21,
            page: 2,
            results: [firstTwenty.last, twentyFirst],
            hasNext: false,
          ),
        ]);
      final container = attachmentContainer(repository: repository);
      final provider = attachmentControllerProvider(employeeId);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);

      await container.read(provider.notifier).loadMore();

      final state = container.read(provider).requireValue;
      expect(state.items, [...firstTwenty, twentyFirst]);
      expect(state.items.map((item) => item.id).toSet(), hasLength(21));
      expect(state.count, 21);
      expect(state.page, 2);
      expect(state.hasNext, isFalse);
      expect(state.isLoadingMore, isFalse);
      expect(repository.requestedPages, [1, 2]);
    },
  );

  test(
    'upload refresh preserves every item already loaded from later pages',
    () async {
      final existing = List.generate(21, (index) => attachmentAt(index + 1));
      final uploaded = attachment_data.EmployeeAttachment(
        id: '10000000-0000-0000-0000-000000000000',
        employeeId: employeeId,
        filename: '最新附件.pdf',
        fileType: 'pdf',
        fileSize: 100,
        uploadedBy: null,
        createdAt: DateTime.utc(2026, 8, 23),
      );
      final repository = FakeAttachmentRepository()
        ..fetchResponses.addAll([
          pagedResponse(
            count: 21,
            page: 1,
            results: existing.take(20).toList(),
            hasNext: true,
          ),
          pagedResponse(
            count: 21,
            page: 2,
            results: [existing.last],
            hasNext: false,
          ),
          pagedResponse(
            count: 22,
            page: 1,
            results: [uploaded, ...existing.take(19)],
            hasNext: true,
          ),
          pagedResponse(
            count: 22,
            page: 2,
            results: existing.skip(19).toList(),
            hasNext: false,
          ),
        ])
        ..uploadResponse = uploaded;
      final picker = FakeAttachmentPicker(
        const attachment_data.AttachmentUploadCandidate(
          path: r'C:\temp\latest.pdf',
          name: 'latest.pdf',
          size: 100,
          extension: 'pdf',
        ),
      );
      final container = attachmentContainer(
        repository: repository,
        picker: picker,
      );
      final listProvider = attachmentControllerProvider(employeeId);
      final listSubscription = container.listen(listProvider, (_, _) {});
      addTearDown(listSubscription.close);
      await container.read(listProvider.future);
      await container.read(listProvider.notifier).loadMore();
      final uploadProvider = attachmentUploadControllerProvider(employeeId);
      await container.read(uploadProvider.future);
      final uploadController = container.read(uploadProvider.notifier);
      await uploadController.chooseFile();

      expect(await uploadController.submit(), isTrue);

      final state = container.read(listProvider).requireValue;
      expect(state.count, 22);
      expect(state.page, 2);
      expect(state.items.map((item) => item.id).toSet(), {
        ...existing.map((item) => item.id),
        uploaded.id,
      });
      expect(state.items.first.id, uploaded.id);
    },
  );

  test(
    'delete refresh keeps the former page-two item without reviving deletion',
    () async {
      final existing = List.generate(21, (index) => attachmentAt(index + 1));
      final repository = FakeAttachmentRepository()
        ..items = List.of(existing)
        ..fetchResponses.addAll([
          pagedResponse(
            count: 21,
            page: 1,
            results: existing.take(20).toList(),
            hasNext: true,
          ),
          pagedResponse(
            count: 21,
            page: 2,
            results: [existing.last],
            hasNext: false,
          ),
          pagedResponse(
            count: 20,
            page: 1,
            results: existing.skip(1).toList(),
            hasNext: false,
          ),
        ]);
      final container = attachmentContainer(repository: repository);
      final provider = attachmentControllerProvider(employeeId);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      await container.read(provider.notifier).loadMore();

      await container.read(provider.notifier).delete(existing.first.id);

      final state = container.read(provider).requireValue;
      expect(state.count, 20);
      expect(state.items, existing.skip(1).toList());
      expect(state.items, contains(existing.last));
      expect(state.items, isNot(contains(existing.first)));
      expect(state.page, 1);
      expect(state.hasNext, isFalse);
    },
  );

  test(
    'disposed attachment controller ignores a late retry completion',
    () async {
      final completion = Completer<attachment_data.AttachmentPage>();
      final repository = FakeAttachmentRepository()
        ..fetchResponses.addAll([pageOf(const []), completion.future]);
      final container = attachmentContainer(repository: repository);
      final provider = attachmentControllerProvider(employeeId);
      final subscription = container.listen(provider, (_, _) {});
      await container.read(provider.future);
      final retrying = container.read(provider.notifier).retry();

      subscription.close();
      await Future<void>.delayed(Duration.zero);
      completion.complete(pageOf([contractAttachment]));

      await expectLater(retrying, completes);
    },
  );

  test('delete protects an in-progress item and refreshes the list', () async {
    final repository = FakeAttachmentRepository()
      ..items = [contractAttachment]
      ..deleteCompleter = Completer<void>();
    final container = attachmentContainer(repository: repository);
    final provider = attachmentControllerProvider(employeeId);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    final controller = container.read(provider.notifier);

    final first = controller.delete(contractAttachment.id);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(provider).value?.deletingIds,
      contains(contractAttachment.id),
    );
    await expectLater(
      controller.delete(contractAttachment.id),
      throwsStateError,
    );

    repository.deleteCompleter!.complete();
    await first;
    expect(container.read(provider).value?.items, isEmpty);
  });

  test(
    'one completed delete preserves another attachment pending guard',
    () async {
      final deleteA = Completer<void>();
      final deleteB = Completer<void>();
      final repository = FakeAttachmentRepository()
        ..items = [contractAttachment, portraitAttachment]
        ..deleteCompleters.addAll({
          contractAttachment.id: deleteA,
          portraitAttachment.id: deleteB,
        });
      final container = attachmentContainer(repository: repository);
      final provider = attachmentControllerProvider(employeeId);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      final controller = container.read(provider.notifier);

      final first = controller.delete(contractAttachment.id);
      final second = controller.delete(portraitAttachment.id);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(provider).value?.deletingIds,
        containsAll([contractAttachment.id, portraitAttachment.id]),
      );

      deleteA.complete();
      await first;
      expect(
        container.read(provider).value?.deletingIds,
        contains(portraitAttachment.id),
      );
      await expectLater(
        controller.delete(portraitAttachment.id),
        throwsStateError,
      );

      deleteB.complete();
      await second;
      expect(container.read(provider).value?.deletingIds, isEmpty);
    },
  );

  test(
    'older delete refresh cannot overwrite a newer empty snapshot',
    () async {
      final deleteA = Completer<void>();
      final deleteB = Completer<void>();
      final olderRefresh = Completer<attachment_data.AttachmentPage>();
      final newerRefresh = Completer<attachment_data.AttachmentPage>();
      final repository = FakeAttachmentRepository()
        ..items = [contractAttachment, portraitAttachment]
        ..fetchResponses.addAll([
          pageOf([contractAttachment, portraitAttachment]),
          olderRefresh.future,
          newerRefresh.future,
        ])
        ..deleteCompleters.addAll({
          contractAttachment.id: deleteA,
          portraitAttachment.id: deleteB,
        });
      final container = attachmentContainer(repository: repository);
      final provider = attachmentControllerProvider(employeeId);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      final controller = container.read(provider.notifier);

      final first = controller.delete(contractAttachment.id);
      final second = controller.delete(portraitAttachment.id);
      deleteA.complete();
      while (repository.fetchCount < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      deleteB.complete();
      while (repository.fetchCount < 3) {
        await Future<void>.delayed(Duration.zero);
      }

      newerRefresh.complete(pageOf(const []));
      await second;
      expect(container.read(provider).value?.items, isEmpty);

      olderRefresh.complete(pageOf([portraitAttachment]));
      await first;

      expect(container.read(provider).value?.items, isEmpty);
      expect(container.read(provider).value?.deletingIds, isEmpty);
      repository.missingDeleteIds.add(portraitAttachment.id);
      await expectLater(
        controller.delete(portraitAttachment.id),
        throwsA(
          isA<Failure>().having(
            (failure) => failure.message,
            'message',
            '附件文件不存在，请重新加载后再试。',
          ),
        ),
      );
    },
  );

  test(
    'download cancellation returns normally through the injected saver',
    () async {
      final repository = FakeAttachmentRepository()
        ..items = [contractAttachment];
      final saver = FakeAttachmentSaver(const AttachmentSaveResult.cancelled());
      final container = attachmentContainer(
        repository: repository,
        saver: saver,
      );
      await container.read(attachmentControllerProvider(employeeId).future);

      final result = await container
          .read(attachmentControllerProvider(employeeId).notifier)
          .download(contractAttachment);

      expect(result.cancelled, isTrue);
      expect(
        container.read(attachmentControllerProvider(employeeId)).hasError,
        isFalse,
      );
    },
  );

  test(
    'download completion after disposal uses the captured saver safely',
    () async {
      final completion = Completer<ApiFileDownload>();
      final repository = FakeAttachmentRepository()
        ..items = [contractAttachment]
        ..downloadResponse = completion.future;
      final saver = FakeAttachmentSaver(const AttachmentSaveResult.cancelled());
      final container = attachmentContainer(
        repository: repository,
        saver: saver,
      );
      final provider = attachmentControllerProvider(employeeId);
      final subscription = container.listen(provider, (_, _) {});
      await container.read(provider.future);
      final downloading = container
          .read(provider.notifier)
          .download(contractAttachment);

      subscription.close();
      await Future<void>.delayed(Duration.zero);
      completion.complete(
        ApiFileDownload(
          bytes: Uint8List.fromList([1]),
          filename: '合同.pdf',
          mimeType: 'application/pdf',
        ),
      );

      expect((await downloading).cancelled, isTrue);
    },
  );

  test('picker cancellation keeps upload state idle', () async {
    final repository = FakeAttachmentRepository();
    final picker = FakeAttachmentPicker(null);
    final container = attachmentContainer(
      repository: repository,
      picker: picker,
    );
    await container.read(attachmentUploadControllerProvider(employeeId).future);

    final selected = await container
        .read(attachmentUploadControllerProvider(employeeId).notifier)
        .chooseFile();

    expect(selected, isFalse);
    final state = container
        .read(attachmentUploadControllerProvider(employeeId))
        .value!;
    expect(state.candidate, isNull);
    expect(state.failure, isNull);
  });

  test('upload controller rejects an invalid local type safely', () async {
    final repository = FakeAttachmentRepository();
    final picker = FakeAttachmentPicker(
      const attachment_data.AttachmentUploadCandidate(
        path: r'C:\temp\payload.exe',
        name: 'payload.exe',
        size: 10 * 1024 * 1024 + 1,
        extension: 'exe',
      ),
    );
    final container = attachmentContainer(
      repository: repository,
      picker: picker,
    );
    await container.read(attachmentUploadControllerProvider(employeeId).future);

    expect(
      await container
          .read(attachmentUploadControllerProvider(employeeId).notifier)
          .chooseFile(),
      isFalse,
    );
    expect(
      container
          .read(attachmentUploadControllerProvider(employeeId))
          .value
          ?.failure
          ?.message,
      '不支持该附件类型，请选择 PDF、DOCX、XLSX、JPG、JPEG 或 PNG 文件。',
    );
  });

  test('upload controller rejects an oversized local file safely', () async {
    final repository = FakeAttachmentRepository();
    final picker = FakeAttachmentPicker(
      const attachment_data.AttachmentUploadCandidate(
        path: r'C:\temp\large.pdf',
        name: 'large.pdf',
        size: 10 * 1024 * 1024 + 1,
        extension: 'pdf',
      ),
    );
    final container = attachmentContainer(
      repository: repository,
      picker: picker,
    );
    await container.read(attachmentUploadControllerProvider(employeeId).future);

    expect(
      await container
          .read(attachmentUploadControllerProvider(employeeId).notifier)
          .chooseFile(),
      isFalse,
    );
    expect(
      container
          .read(attachmentUploadControllerProvider(employeeId))
          .value
          ?.failure
          ?.message,
      '附件大小不能超过 10 MiB。',
    );
  });

  test(
    'upload blocks duplicate submit and refreshes attachment list',
    () async {
      final repository = FakeAttachmentRepository()..items = [];
      final uploadCompleter = Completer<attachment_data.EmployeeAttachment>();
      repository.uploadResponse = uploadCompleter.future;
      final picker = FakeAttachmentPicker(
        const attachment_data.AttachmentUploadCandidate(
          path: r'C:\temp\contract.pdf',
          name: 'contract.pdf',
          size: 1024,
          extension: 'pdf',
        ),
      );
      final container = attachmentContainer(
        repository: repository,
        picker: picker,
      );
      await container.read(attachmentControllerProvider(employeeId).future);
      final controller = container.read(
        attachmentUploadControllerProvider(employeeId).notifier,
      );
      await container.read(
        attachmentUploadControllerProvider(employeeId).future,
      );
      await controller.chooseFile();

      final first = controller.submit();
      final second = controller.submit();
      await expectLater(second, throwsStateError);
      uploadCompleter.complete(contractAttachment);
      await first;
      await container.read(attachmentControllerProvider(employeeId).future);

      expect(
        container.read(attachmentControllerProvider(employeeId)).value?.items,
        hasLength(1),
      );
    },
  );

  test('server upload Failure remains safe and releases submit', () async {
    final repository = FakeAttachmentRepository()
      ..uploadResponse = const Failure.permission();
    final picker = FakeAttachmentPicker(
      const attachment_data.AttachmentUploadCandidate(
        path: r'C:\temp\contract.pdf',
        name: 'contract.pdf',
        size: 1024,
        extension: 'pdf',
      ),
    );
    final container = attachmentContainer(
      repository: repository,
      picker: picker,
    );
    await container.read(attachmentUploadControllerProvider(employeeId).future);
    final controller = container.read(
      attachmentUploadControllerProvider(employeeId).notifier,
    );
    await controller.chooseFile();

    expect(await controller.submit(), isFalse);

    final state = container
        .read(attachmentUploadControllerProvider(employeeId))
        .value!;
    expect(state.isUploading, isFalse);
    expect(state.failure?.message, '当前账号没有权限执行此操作。');
  });

  test('disposed upload controller ignores a late picker completion', () async {
    final repository = FakeAttachmentRepository();
    final completion = Completer<attachment_data.AttachmentUploadCandidate?>();
    final picker = FakeAttachmentPicker(completion.future);
    final container = attachmentContainer(
      repository: repository,
      picker: picker,
    );
    final provider = attachmentUploadControllerProvider(employeeId);
    final subscription = container.listen(provider, (_, _) {});
    await container.read(provider.future);
    final choosing = container.read(provider.notifier).chooseFile();

    subscription.close();
    await Future<void>.delayed(Duration.zero);
    completion.complete(
      const attachment_data.AttachmentUploadCandidate(
        path: r'C:\temp\late.pdf',
        name: 'late.pdf',
        size: 1024,
        extension: 'pdf',
      ),
    );

    expect(await choosing, isFalse);
  });

  test('disposed upload controller ignores a late submit completion', () async {
    final repository = FakeAttachmentRepository();
    final completion = Completer<attachment_data.EmployeeAttachment>();
    repository.uploadResponse = completion.future;
    final picker = FakeAttachmentPicker(
      const attachment_data.AttachmentUploadCandidate(
        path: r'C:\temp\pending.pdf',
        name: 'pending.pdf',
        size: 1024,
        extension: 'pdf',
      ),
    );
    final container = attachmentContainer(
      repository: repository,
      picker: picker,
    );
    final provider = attachmentUploadControllerProvider(employeeId);
    final subscription = container.listen(provider, (_, _) {});
    await container.read(provider.future);
    final controller = container.read(provider.notifier);
    await controller.chooseFile();
    final submitting = controller.submit();

    subscription.close();
    await Future<void>.delayed(Duration.zero);
    completion.complete(contractAttachment);

    expect(await submitting, isTrue);
  });

  test(
    'upload completion after page exit refreshes a live attachment list',
    () async {
      final repository = FakeAttachmentRepository()..items = [];
      final completion = Completer<attachment_data.EmployeeAttachment>();
      repository.uploadResponse = completion.future;
      final picker = FakeAttachmentPicker(
        const attachment_data.AttachmentUploadCandidate(
          path: r'C:\temp\pending.pdf',
          name: 'pending.pdf',
          size: 1024,
          extension: 'pdf',
        ),
      );
      final container = attachmentContainer(
        repository: repository,
        picker: picker,
      );
      final listProvider = attachmentControllerProvider(employeeId);
      final listSubscription = container.listen(listProvider, (_, _) {});
      addTearDown(listSubscription.close);
      await container.read(listProvider.future);
      expect(repository.fetchCount, 1);

      final uploadProvider = attachmentUploadControllerProvider(employeeId);
      final uploadSubscription = container.listen(uploadProvider, (_, _) {});
      await container.read(uploadProvider.future);
      final uploadController = container.read(uploadProvider.notifier);
      await uploadController.chooseFile();
      final submitting = uploadController.submit();

      uploadSubscription.close();
      await Future<void>.delayed(Duration.zero);
      completion.complete(contractAttachment);
      expect(await submitting, isTrue);
      await container.read(listProvider.future);

      expect(repository.fetchCount, 2);
      expect(container.read(listProvider).value?.items, [contractAttachment]);
    },
  );

  test('failed replacement clears the prior valid upload candidate', () async {
    final repository = FakeAttachmentRepository();
    final picker = FakeAttachmentPicker(
      const attachment_data.AttachmentUploadCandidate(
        path: r'C:\temp\valid-a.pdf',
        name: 'valid-a.pdf',
        size: 1024,
        extension: 'pdf',
      ),
    );
    final container = attachmentContainer(
      repository: repository,
      picker: picker,
    );
    final provider = attachmentUploadControllerProvider(employeeId);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    final controller = container.read(provider.notifier);
    expect(await controller.chooseFile(), isTrue);

    picker.response = const attachment_data.AttachmentUploadCandidate(
      path: r'C:\temp\invalid-b.exe',
      name: 'invalid-b.exe',
      size: 1024,
      extension: 'exe',
    );
    expect(await controller.chooseFile(), isFalse);

    final state = container.read(provider).value!;
    expect(state.candidate, isNull);
    expect(
      state.failure?.message,
      '不支持该附件类型，请选择 PDF、DOCX、XLSX、JPG、JPEG 或 PNG 文件。',
    );
    expect(await controller.submit(), isFalse);
  });

  test(
    'latest file selection wins when picker completions are reversed',
    () async {
      final repository = FakeAttachmentRepository();
      final firstCompletion =
          Completer<attachment_data.AttachmentUploadCandidate?>();
      final secondCompletion =
          Completer<attachment_data.AttachmentUploadCandidate?>();
      final picker = QueuedAttachmentPicker([
        firstCompletion.future,
        secondCompletion.future,
      ]);
      final container = attachmentContainer(
        repository: repository,
        picker: picker,
      );
      final provider = attachmentUploadControllerProvider(employeeId);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      final controller = container.read(provider.notifier);

      final first = controller.chooseFile();
      final second = controller.chooseFile();
      secondCompletion.complete(
        const attachment_data.AttachmentUploadCandidate(
          path: r'C:\temp\latest-b.pdf',
          name: 'latest-b.pdf',
          size: 2048,
          extension: 'pdf',
        ),
      );
      expect(await second, isTrue);
      firstCompletion.complete(
        const attachment_data.AttachmentUploadCandidate(
          path: r'C:\temp\stale-a.pdf',
          name: 'stale-a.pdf',
          size: 1024,
          extension: 'pdf',
        ),
      );
      expect(await first, isFalse);

      expect(container.read(provider).value?.candidate?.name, 'latest-b.pdf');
    },
  );
}
