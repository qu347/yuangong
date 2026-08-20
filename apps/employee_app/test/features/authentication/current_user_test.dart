import 'package:employee_app/features/authentication/data/current_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing audit export capability defaults to false', () {
    final user = CurrentUser.fromJson({
      'id': '00000000-0000-0000-0000-000000000101',
      'username': 'legacy.user',
      'display_name': '旧客户端用户',
      'employee_id': null,
      'employee_no': null,
      'department': null,
      'roles': ['employee'],
      'capabilities': {'can_view_audit': true},
    });

    expect(user.capabilities.canExportAudit, isFalse);
  });
}
