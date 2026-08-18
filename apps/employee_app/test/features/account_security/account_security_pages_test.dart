import 'package:employee_app/core/errors/failure.dart';
import 'package:employee_app/features/account_security/data/account_security_repository.dart';
import 'package:employee_app/features/account_security/data/account_session.dart';
import 'package:employee_app/features/account_security/presentation/accept_invitation_page.dart';
import 'package:employee_app/features/account_security/presentation/account_security_controller.dart';
import 'package:employee_app/features/account_security/presentation/forgot_password_page.dart';
import 'package:employee_app/features/account_security/presentation/password_fields.dart';
import 'package:employee_app/features/account_security/presentation/session_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAccountSecurityRepository implements AccountSecurityRepository {
  final sessions = <AccountSession>[];
  Object? sessionsError;
  Object? invitationError;

  @override
  Future<void> acceptInvitation({
    required String token,
    required String newPassword,
  }) async {
    if (invitationError case final error?) throw error;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {}

  @override
  Future<List<AccountSession>> fetchSessions() async {
    if (sessionsError case final error?) throw error;
    return sessions;
  }

  @override
  Future<String> requestPasswordReset(String identifier) async =>
      '如果账号符合条件，系统会发送密码重置邮件。';

  @override
  Future<int> revokeOtherSessions() async => 0;

  @override
  Future<bool> revokeSession(String id) async => true;
}

void main() {
  test('password hints reject short and numeric-only values', () {
    expect(validateStrongPassword('short'), '密码至少需要 12 个字符');
    expect(validateStrongPassword('123456789012'), '密码不能是纯数字');
    expect(validateStrongPassword('Quartz!Forest7Harbor'), isNull);
  });

  testWidgets('forgot password always shows generic success message', (
    tester,
  ) async {
    final repository = FakeAccountSecurityRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSecurityRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ForgotPasswordPage()),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('forgot_identifier')),
      'unknown@example.invalid',
    );
    await tester.tap(find.byKey(const Key('forgot_submit')));
    await tester.pumpAndSettle();

    expect(find.text('如果账号符合条件，系统会发送密码重置邮件。'), findsOneWidget);
  });

  testWidgets(
    'session list marks the current device without token identifiers',
    (tester) async {
      final repository = FakeAccountSecurityRepository()
        ..sessions.add(
          AccountSession(
            id: 'session-id',
            clientPlatform: 'windows',
            clientName: 'Windows 客户端',
            appVersion: '0.1.0',
            createdAt: DateTime(2026, 8, 18),
            lastSeenAt: DateTime(2026, 8, 18, 8, 5),
            expiresAt: DateTime(2026, 8, 25),
            isCurrent: true,
          ),
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountSecurityRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: Scaffold(body: SessionListPage())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Windows 客户端'), findsOneWidget);
      expect(find.text('当前设备'), findsOneWidget);
      expect(find.textContaining('token'), findsNothing);
    },
  );

  testWidgets('expired invitation shows a safe error and keeps form input', (
    tester,
  ) async {
    final repository = FakeAccountSecurityRepository()
      ..invitationError = const Failure.validation('一次性代码无效或密码不符合安全要求。');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSecurityRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: AcceptInvitationPage()),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('invitation_token')),
      'expired-invitation-code',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '新密码'),
      'Quartz!Forest7Harbor',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '确认新密码'),
      'Quartz!Forest7Harbor',
    );
    await tester.tap(find.byKey(const Key('invitation_accept_submit')));
    await tester.pumpAndSettle();

    expect(find.text('一次性代码无效或密码不符合安全要求。'), findsOneWidget);
    expect(find.text('expired-invitation-code'), findsOneWidget);
  });

  testWidgets('session list exposes empty and safe error states', (
    tester,
  ) async {
    final repository = FakeAccountSecurityRepository();
    final container = ProviderContainer(
      overrides: [
        accountSecurityRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SessionListPage())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无登录会话'), findsOneWidget);

    repository.sessionsError = const Failure(
      type: FailureType.network,
      message: '会话网络失败。',
    );
    container.invalidate(accountSessionListProvider);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('会话网络失败。'), findsOneWidget);
  });
}
