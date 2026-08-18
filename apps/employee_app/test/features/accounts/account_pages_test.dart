import 'package:employee_app/features/accounts/data/account.dart';
import 'package:employee_app/features/accounts/data/account_repository.dart';
import 'package:employee_app/features/accounts/presentation/account_detail_page.dart';
import 'package:employee_app/features/accounts/presentation/account_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAccountRepository implements AccountRepository {
  var resendCount = 0;
  var revokeCount = 0;
  var updateEmailCount = 0;
  var deactivateCount = 0;
  var roleChangeCount = 0;

  static final invitation = AccountInvitation(
    id: 'invitation-id',
    employeeId: 'employee-id',
    email: 'invite@example.invalid',
    username: 'invite.account',
    targetRole: 'employee',
    status: 'pending',
    expiresAt: DateTime.utc(2026, 8, 20),
    sendCount: 1,
  );

  static const account = Account(
    id: 'account-id',
    username: 'managed.account',
    email: 'managed.account@example.invalid',
    isActive: true,
    lastLogin: null,
    employee: null,
    role: 'employee',
    hasActiveInvitation: false,
    emailMismatch: false,
    isManageable: true,
  );

  @override
  Future<AccountPage> fetchAccounts({
    String search = '',
    String? role,
    bool? isActive,
    int page = 1,
  }) async => const AccountPage(count: 0, results: []);

  @override
  Future<List<AccountInvitation>> fetchInvitations() async => [invitation];

  @override
  Future<AccountInvitation> resendInvitation(String id) async {
    resendCount += 1;
    return invitation;
  }

  @override
  Future<bool> revokeInvitation(String id) async {
    revokeCount += 1;
    return true;
  }

  @override
  Future<Account> changeRole(String id, String role) async {
    roleChangeCount += 1;
    return account;
  }

  @override
  Future<AccountInvitation> createInvitation({
    required String employeeId,
    required String username,
    required String email,
    required String role,
  }) => throw UnimplementedError();

  @override
  Future<Account> fetchAccount(String id) async => account;

  @override
  Future<int> revokeSessions(String id) => throw UnimplementedError();

  @override
  Future<Account> setActive(String id, {required bool active}) async {
    if (!active) deactivateCount += 1;
    return account;
  }

  @override
  Future<Account> updateEmail(String id, String email) async {
    updateEmailCount += 1;
    return account;
  }
}

void main() {
  testWidgets('lists pending invitations and confirms resend and revoke', (
    tester,
  ) async {
    final repository = FakeAccountRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: Scaffold(body: AccountListPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('邀请管理'));
    await tester.pumpAndSettle();
    expect(find.text('invite.account'), findsOneWidget);
    expect(find.textContaining('invite@example.invalid'), findsOneWidget);

    await tester.tap(find.byKey(const Key('invitation_resend_invitation-id')));
    await tester.pumpAndSettle();
    expect(find.text('确认重发邀请？'), findsOneWidget);
    await tester.tap(find.text('确认重发'));
    await tester.pumpAndSettle();
    expect(repository.resendCount, 1);

    await tester.tap(find.byKey(const Key('invitation_revoke_invitation-id')));
    await tester.pumpAndSettle();
    expect(find.text('确认撤销邀请？'), findsOneWidget);
    await tester.tap(find.text('确认撤销'));
    await tester.pumpAndSettle();
    expect(repository.revokeCount, 1);
  });

  testWidgets('account detail edits email and confirms lifecycle actions', (
    tester,
  ) async {
    final repository = FakeAccountRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: Scaffold(body: AccountDetailPage(accountId: 'account-id')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('account_email')),
      'updated.account@example.invalid',
    );
    await tester.tap(find.byKey(const Key('account_email_save')));
    await tester.pumpAndSettle();
    expect(repository.updateEmailCount, 1);

    await tester.tap(find.byKey(const Key('account_role')));
    await tester.pumpAndSettle();
    expect(find.text('system_admin'), findsNothing);
    await tester.tap(find.text('hr_admin').last);
    await tester.pumpAndSettle();
    expect(find.text('确认调整角色？'), findsOneWidget);
    await tester.tap(find.text('确认调整'));
    await tester.pumpAndSettle();
    expect(repository.roleChangeCount, 1);

    await tester.tap(find.byKey(const Key('account_deactivate')));
    await tester.pumpAndSettle();
    expect(find.text('确认停用账号？'), findsOneWidget);
    await tester.tap(find.text('确认停用'));
    await tester.pumpAndSettle();
    expect(repository.deactivateCount, 1);
  });
}
