import 'dart:typed_data';

import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/features/attachments/data/attachment.dart'
    as attachment_data;
import 'package:employee_app/features/attachments/data/attachment_repository.dart';
import 'package:employee_app/features/attachments/platform/attachment_file_picker.dart';
import 'package:employee_app/features/attachments/platform/attachment_file_saver.dart';
import 'package:employee_app/features/attachments/presentation/attachment_page.dart';
import 'package:employee_app/features/attachments/presentation/attachment_upload_page.dart';
import 'package:employee_app/features/attachments/presentation/employee_attachment_section.dart';
import 'package:employee_app/features/authentication/data/current_user.dart';
import 'package:employee_app/features/authentication/presentation/auth_session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const employeeId = '20000000-0000-0000-0000-000000000001';

final contractAttachment = attachment_data.EmployeeAttachment(
  id: '10000000-0000-0000-0000-000000000001',
  employeeId: employeeId,
  filename: '合同.pdf',
  fileType: 'pdf',
  fileSize: 1024,
  uploadedBy: null,
  createdAt: DateTime.utc(2026, 8, 21),
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

class WidgetAttachmentRepository implements AttachmentRepository {
  WidgetAttachmentRepository(this.response);

  Object response;
  int requestCount = 0;
  final requestedPages = <int>[];

  @override
  Future<attachment_data.AttachmentPage> fetchAttachments(
    String employeeId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    requestCount += 1;
    requestedPages.add(page);
    final current = response;
    if (current is attachment_data.AttachmentPage) {
      return current;
    }
    if (current is List<attachment_data.AttachmentPage>) {
      return current[page - 1];
    }
    throw current;
  }

  @override
  Future<void> deleteAttachment(String attachmentId) async {}

  @override
  Future<ApiFileDownload> downloadAttachment(
    String attachmentId, {
    required String fileType,
  }) async => ApiFileDownload(
    bytes: Uint8List.fromList([1]),
    filename: '合同.pdf',
    mimeType: 'application/pdf',
  );

  @override
  Future<attachment_data.EmployeeAttachment> uploadAttachment(
    String employeeId,
    attachment_data.AttachmentUploadCandidate candidate,
  ) async => contractAttachment;
}

class WidgetAttachmentPicker implements AttachmentFilePicker {
  @override
  Future<attachment_data.AttachmentUploadCandidate?> pick() async =>
      const attachment_data.AttachmentUploadCandidate(
        path: r'C:\temp\contract.pdf',
        name: '合同.pdf',
        size: 1024,
        extension: 'pdf',
      );
}

class WidgetAttachmentSaver implements AttachmentFileSaver {
  WidgetAttachmentSaver([
    this.response = const AttachmentSaveResult.cancelled(),
  ]);

  final Object response;

  @override
  Future<AttachmentSaveResult> save(
    Uint8List bytes,
    String filename,
    String mimeType,
  ) async {
    final current = response;
    if (current is AttachmentSaveResult) {
      return current;
    }
    throw current;
  }
}

AuthSessionStore sessionStore({required bool canManage}) {
  final store = AuthSessionStore();
  store.markAuthenticated(
    CurrentUser(
      id: 'user-id',
      username: canManage ? 'hr.manager' : 'employee.self',
      displayName: canManage ? '人事管理员' : '员工本人',
      employeeId: canManage ? null : employeeId,
      employeeNo: canManage ? null : 'EMP-0001',
      department: null,
      roles: [canManage ? 'hr_admin' : 'employee'],
      capabilities: canManage
          ? const UserCapabilities(
              canManageEmployees: true,
              canManageDepartments: true,
              canManagePositions: true,
              canViewAudit: true,
              canLogoutAll: true,
            )
          : const UserCapabilities.none(),
    ),
  );
  return store;
}

Widget pageHarness({
  required WidgetAttachmentRepository repository,
  required bool canManage,
  Widget? page,
  AttachmentFileSaver? saver,
}) {
  final store = sessionStore(canManage: canManage);
  return ProviderScope(
    overrides: [
      authSessionStoreProvider.overrideWithValue(store),
      attachmentRepositoryProvider.overrideWithValue(repository),
      attachmentFilePickerProvider.overrideWithValue(WidgetAttachmentPicker()),
      attachmentFileSaverProvider.overrideWithValue(
        saver ?? WidgetAttachmentSaver(),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: page ?? const AttachmentPage(employeeId: employeeId),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'employee attachment page shows safe metadata and manager actions',
    (tester) async {
      final repository = WidgetAttachmentRepository(
        attachment_data.AttachmentPage(
          count: 1,
          next: null,
          previous: null,
          results: [contractAttachment],
        ),
      );

      await tester.pumpWidget(
        pageHarness(repository: repository, canManage: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('员工附件'), findsOneWidget);
      expect(find.text('合同.pdf'), findsOneWidget);
      expect(find.text('1.0 KB'), findsOneWidget);
      expect(find.text('上传附件'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('下载'), findsOneWidget);
    },
  );

  testWidgets('load more makes the twenty-first attachment reachable', (
    tester,
  ) async {
    final firstTwenty = List.generate(20, (index) => attachmentAt(index + 1));
    final twentyFirst = attachmentAt(21);
    final repository = WidgetAttachmentRepository([
      attachment_data.AttachmentPage(
        count: 21,
        next: 'https://api.example.test/attachments/?page=2',
        previous: null,
        results: firstTwenty,
      ),
      attachment_data.AttachmentPage(
        count: 21,
        next: null,
        previous: 'https://api.example.test/attachments/?page=1',
        results: [twentyFirst],
      ),
    ]);

    await tester.pumpWidget(
      pageHarness(repository: repository, canManage: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('附件-21.pdf'), findsNothing);
    for (
      var attempt = 0;
      attempt < 20 && find.text('加载更多').evaluate().isEmpty;
      attempt += 1
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump();
    }
    expect(find.text('加载更多'), findsOneWidget);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();

    expect(find.text('附件-21.pdf'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
    expect(repository.requestedPages, [1, 2]);
  });

  testWidgets(
    'employee self can list and download but cannot mutate attachments',
    (tester) async {
      final repository = WidgetAttachmentRepository(
        attachment_data.AttachmentPage(
          count: 1,
          next: null,
          previous: null,
          results: [contractAttachment],
        ),
      );

      await tester.pumpWidget(
        pageHarness(repository: repository, canManage: false),
      );
      await tester.pumpAndSettle();

      expect(find.text('合同.pdf'), findsOneWidget);
      expect(find.text('下载'), findsOneWidget);
      expect(find.text('上传附件'), findsNothing);
      expect(find.text('删除'), findsNothing);
    },
  );

  testWidgets('attachment page shows empty and retry states', (tester) async {
    final repository = WidgetAttachmentRepository(const Failure.network());

    await tester.pumpWidget(
      pageHarness(repository: repository, canManage: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法连接后端服务，请检查服务是否启动。'), findsOneWidget);

    repository.response = const attachment_data.AttachmentPage(
      count: 0,
      next: null,
      previous: null,
      results: [],
    );
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('暂无附件'), findsOneWidget);
    expect(repository.requestCount, 2);
  });

  testWidgets('unknown saver error shows a safe message without escaping', (
    tester,
  ) async {
    final repository = WidgetAttachmentRepository(
      attachment_data.AttachmentPage(
        count: 1,
        next: null,
        previous: null,
        results: [contractAttachment],
      ),
    );

    await tester.pumpWidget(
      pageHarness(
        repository: repository,
        canManage: false,
        saver: WidgetAttachmentSaver(
          StateError('sensitive injected saver detail'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();

    expect(find.text('附件保存失败，请稍后重试。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('upload page previews selected name size type', (tester) async {
    final repository = WidgetAttachmentRepository(
      const attachment_data.AttachmentPage(
        count: 0,
        next: null,
        previous: null,
        results: [],
      ),
    );

    await tester.pumpWidget(
      pageHarness(
        repository: repository,
        canManage: true,
        page: const AttachmentUploadPage(employeeId: employeeId),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();

    expect(find.text('合同.pdf'), findsOneWidget);
    expect(find.text('1.0 KB'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('上传'), findsOneWidget);
  });

  testWidgets('manager attachment page fits an Android-width viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = WidgetAttachmentRepository(
      attachment_data.AttachmentPage(
        count: 1,
        next: null,
        previous: null,
        results: [contractAttachment],
      ),
    );

    await tester.pumpWidget(
      pageHarness(repository: repository, canManage: true),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('attachment detail entry fits an Android-width viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: EmployeeAttachmentSection(employeeId: employeeId)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving and reopening upload clears the local candidate', (
    tester,
  ) async {
    final repository = WidgetAttachmentRepository(
      const attachment_data.AttachmentPage(
        count: 0,
        next: null,
        previous: null,
        results: [],
      ),
    );
    final store = sessionStore(canManage: true);
    final container = ProviderContainer(
      overrides: [
        authSessionStoreProvider.overrideWithValue(store),
        attachmentRepositoryProvider.overrideWithValue(repository),
        attachmentFilePickerProvider.overrideWithValue(
          WidgetAttachmentPicker(),
        ),
        attachmentFileSaverProvider.overrideWithValue(WidgetAttachmentSaver()),
      ],
    );
    addTearDown(container.dispose);

    Widget app(Widget child) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    );

    await tester.pumpWidget(
      app(const AttachmentUploadPage(employeeId: employeeId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();
    expect(find.text('合同.pdf'), findsOneWidget);

    await tester.pumpWidget(app(const SizedBox.shrink()));
    await tester.pump();
    await tester.pumpWidget(
      app(const AttachmentUploadPage(employeeId: employeeId)),
    );
    await tester.pumpAndSettle();

    expect(find.text('合同.pdf'), findsNothing);
  });

  testWidgets('logout then another login refetches the same employee key', (
    tester,
  ) async {
    final repository = WidgetAttachmentRepository(
      attachment_data.AttachmentPage(
        count: 1,
        next: null,
        previous: null,
        results: [contractAttachment],
      ),
    );
    final store = sessionStore(canManage: true);
    final container = ProviderContainer(
      overrides: [
        authSessionStoreProvider.overrideWithValue(store),
        attachmentRepositoryProvider.overrideWithValue(repository),
        attachmentFileSaverProvider.overrideWithValue(WidgetAttachmentSaver()),
      ],
    );
    addTearDown(container.dispose);

    Widget app(Widget child) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    );

    await tester.pumpWidget(app(const AttachmentPage(employeeId: employeeId)));
    await tester.pumpAndSettle();
    expect(find.text('合同.pdf'), findsOneWidget);
    expect(repository.requestCount, 1);

    store.markUnauthenticated();
    await tester.pumpWidget(app(const SizedBox.shrink()));
    await tester.pump();
    repository.response = const attachment_data.AttachmentPage(
      count: 0,
      next: null,
      previous: null,
      results: [],
    );
    store.markAuthenticated(
      const CurrentUser(
        id: 'ordinary-user-id',
        username: 'ordinary.employee',
        displayName: '普通员工',
        employeeId: employeeId,
        employeeNo: 'EMP-0001',
        department: null,
        roles: ['employee'],
      ),
    );
    await tester.pumpWidget(app(const AttachmentPage(employeeId: employeeId)));
    await tester.pumpAndSettle();

    expect(repository.requestCount, 2);
    expect(find.text('合同.pdf'), findsNothing);
    expect(find.text('暂无附件'), findsOneWidget);
  });
}
