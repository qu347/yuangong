import 'dart:typed_data';

import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/features/audit/data/audit_event.dart';
import 'package:employee_app/features/audit/data/audit_export_repository.dart';
import 'package:employee_app/features/audit/data/audit_repository.dart';
import 'package:employee_app/features/audit/platform/audit_export_saver.dart';
import 'package:employee_app/features/audit/presentation/audit_page.dart';
import 'package:employee_app/features/authentication/data/current_user.dart';
import 'package:employee_app/features/authentication/presentation/auth_session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class EmptyAuditRepository implements AuditRepository {
  @override
  Future<AuditEventPage> fetchAuditEvents({
    String? action,
    String? resourceType,
    int page = 1,
    int pageSize = 20,
  }) async => const AuditEventPage(count: 0, results: []);
}

class PageExportRepository implements AuditExportRepository {
  var calls = 0;
  Object? error;

  @override
  Future<ApiDownload> export(AuditExportFilters filters) async {
    calls += 1;
    if (error case final failure?) throw failure;
    return ApiDownload(
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: 'audit-events-safe.csv',
    );
  }
}

class PageExportSaver implements AuditExportSaver {
  var calls = 0;
  AuditSaveResult result = const AuditSaveResult.saved('memory://audit.csv');

  @override
  Future<AuditSaveResult> save(Uint8List bytes, String filename) async {
    calls += 1;
    return result;
  }
}

Widget auditApp({
  required bool canExport,
  required PageExportRepository exportRepository,
  required PageExportSaver saver,
}) {
  final store = AuthSessionStore()
    ..markAuthenticated(
      CurrentUser(
        id: 'user-id',
        username: 'audit-user',
        displayName: '审计用户',
        employeeId: null,
        employeeNo: null,
        department: null,
        roles: const ['system_admin'],
        capabilities: UserCapabilities(
          canManageEmployees: false,
          canManageDepartments: false,
          canManagePositions: false,
          canViewAudit: true,
          canLogoutAll: true,
          canExportAudit: canExport,
        ),
      ),
    );
  return ProviderScope(
    overrides: [
      authSessionStoreProvider.overrideWithValue(store),
      auditRepositoryProvider.overrideWithValue(EmptyAuditRepository()),
      auditExportRepositoryProvider.overrideWithValue(exportRepository),
      auditExportSaverProvider.overrideWithValue(saver),
    ],
    child: const MaterialApp(home: Scaffold(body: AuditPage())),
  );
}

void main() {
  testWidgets('employee and hr capability state hides audit export', (
    tester,
  ) async {
    await tester.pumpWidget(
      auditApp(
        canExport: false,
        exportRepository: PageExportRepository(),
        saver: PageExportSaver(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('audit_export')), findsNothing);
  });

  testWidgets('system admin confirms and saves audit export', (tester) async {
    final repository = PageExportRepository();
    final saver = PageExportSaver();
    await tester.pumpWidget(
      auditApp(canExport: true, exportRepository: repository, saver: saver),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('audit_export')));
    await tester.pumpAndSettle();
    expect(find.text('确认导出审计？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repository.calls, 0);

    await tester.tap(find.byKey(const Key('audit_export')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认导出'));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(saver.calls, 1);
    expect(find.textContaining('memory://audit.csv'), findsOneWidget);
  });

  testWidgets('save cancellation and server failure show safe messages', (
    tester,
  ) async {
    final repository = PageExportRepository();
    final saver = PageExportSaver()..result = const AuditSaveResult.cancelled();
    await tester.pumpWidget(
      auditApp(canExport: true, exportRepository: repository, saver: saver),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('audit_export')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认导出'));
    await tester.pumpAndSettle();
    expect(find.text('已取消保存。'), findsOneWidget);

    repository.error = const Failure.validation('审计记录超过导出上限，请缩小筛选范围后重试。');
    await tester.tap(find.byKey(const Key('audit_export')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认导出'));
    await tester.pumpAndSettle();
    expect(find.text('审计记录超过导出上限，请缩小筛选范围后重试。'), findsOneWidget);
  });
}
