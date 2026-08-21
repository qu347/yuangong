import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../authentication/presentation/auth_controller.dart';

final currentEmployeeIdProvider = Provider<String?>((ref) {
  return ref.watch(authControllerProvider).value?.employeeId;
});

class EmployeeAttachmentSection extends StatelessWidget {
  const EmployeeAttachmentSection({required this.employeeId, super.key});

  final String employeeId;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            const Icon(Icons.folder_copy_outlined),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('员工附件', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  const Text('查看合同、表格、图片等已授权文件。'),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () =>
                  context.push('/employees/$employeeId/attachments'),
              icon: const Icon(Icons.chevron_right_rounded),
              label: const Text('查看附件'),
            ),
          ],
        ),
      ),
    );
  }
}
