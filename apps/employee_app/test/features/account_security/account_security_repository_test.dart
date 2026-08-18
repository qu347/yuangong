import 'package:employee_app/core/network/api_client.dart';
import 'package:employee_app/core/network/api_endpoints.dart';
import 'package:employee_app/features/account_security/data/account_security_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSecurityApiClient extends Mock implements ApiClient {}

void main() {
  test(
    'public recovery methods use unauthenticated shared ApiClient',
    () async {
      final apiClient = MockSecurityApiClient();
      final repository = NetworkAccountSecurityRepository(apiClient);
      when(
        () => apiClient.postVoid(
          ApiEndpoints.invitationAccept,
          data: any(named: 'data'),
          authenticated: false,
        ),
      ).thenAnswer((_) async {});
      when(
        () => apiClient.postMap(
          ApiEndpoints.passwordResetRequest,
          data: any(named: 'data'),
          authenticated: false,
        ),
      ).thenAnswer((_) async => {'message': '如果账号符合条件，系统会发送密码重置邮件。'});
      when(
        () => apiClient.postVoid(
          ApiEndpoints.passwordResetConfirm,
          data: any(named: 'data'),
          authenticated: false,
        ),
      ).thenAnswer((_) async {});

      await repository.acceptInvitation(
        token: ' invitation-code ',
        newPassword: 'strong-password',
      );
      final message = await repository.requestPasswordReset(
        'employee@example.invalid',
      );
      await repository.confirmPasswordReset(
        token: ' reset-code ',
        newPassword: 'new-password',
      );

      expect(message, '如果账号符合条件，系统会发送密码重置邮件。');
      verify(
        () => apiClient.postVoid(
          ApiEndpoints.invitationAccept,
          data: {'token': 'invitation-code', 'new_password': 'strong-password'},
          authenticated: false,
        ),
      ).called(1);
    },
  );

  test('parses sessions without exposing token identifiers', () async {
    final apiClient = MockSecurityApiClient();
    final repository = NetworkAccountSecurityRepository(apiClient);
    when(() => apiClient.getList(ApiEndpoints.sessions)).thenAnswer(
      (_) async => [
        {
          'id': '00000000-0000-0000-0000-000000000701',
          'client_platform': 'windows',
          'client_name': 'Windows 客户端',
          'app_version': '0.1.0',
          'created_at': '2026-08-18T08:00:00Z',
          'last_seen_at': '2026-08-18T08:05:00Z',
          'expires_at': '2026-08-25T08:00:00Z',
          'is_current': true,
        },
      ],
    );

    final sessions = await repository.fetchSessions();

    expect(sessions.single.isCurrent, isTrue);
    expect(sessions.single.clientPlatform, 'windows');
  });
}
