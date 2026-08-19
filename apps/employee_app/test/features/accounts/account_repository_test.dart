import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/core/network/api_endpoints.dart';
import 'package:employee_app/features/accounts/data/account_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAccountApiClient extends Mock implements ApiClient {}

const accountJson = <String, dynamic>{
  'id': '00000000-0000-0000-0000-000000000801',
  'username': 'managed.account',
  'email': 'managed.account@example.invalid',
  'is_active': true,
  'last_login': null,
  'employee': {
    'id': '00000000-0000-0000-0000-000000000201',
    'employee_no': 'EMP-0001',
    'full_name': '虚构账号员工',
    'employment_status': 'active',
    'work_email': 'directory.account@example.invalid',
  },
  'role': 'employee',
  'has_active_invitation': false,
  'email_mismatch': true,
  'is_manageable': true,
};

const invitationJson = <String, dynamic>{
  'id': '00000000-0000-0000-0000-000000000901',
  'employee_id': '00000000-0000-0000-0000-000000000201',
  'email': 'invite@example.invalid',
  'username': 'invite.account',
  'target_role': 'employee',
  'status': 'pending',
  'expires_at': '2026-08-20T08:00:00Z',
  'send_count': 1,
  'last_sent_at': '2026-08-18T08:00:00Z',
  'created_at': '2026-08-18T08:00:00Z',
  'updated_at': '2026-08-18T08:00:00Z',
};

void main() {
  test('loads paginated accounts and parses safe fields', () async {
    final apiClient = MockAccountApiClient();
    final repository = NetworkAccountRepository(apiClient);
    when(
      () => apiClient.getMap(
        ApiEndpoints.accounts,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => {
        'count': 1,
        'next': null,
        'previous': null,
        'results': [accountJson],
      },
    );

    final page = await repository.fetchAccounts(
      search: 'managed',
      role: 'employee',
    );

    expect(page.count, 1);
    expect(page.results.single.role, 'employee');
    expect(page.results.single.emailMismatch, isTrue);
    expect(page.results.single.employee?.employeeNo, 'EMP-0001');
  });

  test('creates invitation without expecting raw token response', () async {
    final apiClient = MockAccountApiClient();
    final repository = NetworkAccountRepository(apiClient);
    when(
      () =>
          apiClient.postMap(ApiEndpoints.invitations, data: any(named: 'data')),
    ).thenAnswer((_) async => invitationJson);

    final invitation = await repository.createInvitation(
      employeeId: '00000000-0000-0000-0000-000000000201',
      username: 'invite.account',
      email: 'invite@example.invalid',
      role: 'employee',
    );

    expect(invitation.status, 'pending');
    expect(invitation.username, 'invite.account');
  });

  test('loads invitations for resend and revoke management', () async {
    final apiClient = MockAccountApiClient();
    final repository = NetworkAccountRepository(apiClient);
    when(
      () => apiClient.getList(ApiEndpoints.invitations),
    ).thenAnswer((_) async => [invitationJson]);

    final invitations = await repository.fetchInvitations();

    expect(invitations, hasLength(1));
    expect(invitations.single.status, 'pending');
    expect(invitations.single.sendCount, 1);
  });
}
