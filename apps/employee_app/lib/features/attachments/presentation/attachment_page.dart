import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../../authentication/presentation/auth_session_store.dart';
import '../data/attachment.dart' as attachment_data;
import 'attachment_controller.dart';

class AttachmentPage extends ConsumerWidget {
  const AttachmentPage({required this.employeeId, super.key});

  final String employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachments = ref.watch(attachmentControllerProvider(employeeId));
    final canManage = ref
        .watch(authSessionStoreProvider)
        .capabilities
        .canManageEmployees;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '返回员工详情',
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/employees/$employeeId');
                        }
                      },
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '员工附件',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    if (canManage)
                      FilledButton.icon(
                        onPressed: () => context.push(
                          '/employees/$employeeId/attachments/upload',
                        ),
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('上传附件'),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: attachments.when(
                    loading: () =>
                        const Center(child: AppLoadingView(label: '正在加载员工附件')),
                    error: (error, _) => Align(
                      alignment: Alignment.topLeft,
                      child: AppErrorView(
                        message: error is Failure
                            ? error.message
                            : '员工附件加载失败，请稍后重试。',
                        onRetry: () => ref
                            .read(
                              attachmentControllerProvider(employeeId).notifier,
                            )
                            .retry(),
                      ),
                    ),
                    data: (state) {
                      if (state.items.isEmpty) {
                        return const Center(child: Text('暂无附件'));
                      }
                      return ListView.separated(
                        itemCount: state.items.length + (state.hasNext ? 1 : 0),
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          if (index == state.items.length) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: OutlinedButton.icon(
                                  onPressed: state.isLoadingMore
                                      ? null
                                      : () => _loadMore(context, ref),
                                  icon: state.isLoadingMore
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.expand_more),
                                  label: Text(
                                    state.isLoadingMore ? '正在加载' : '加载更多',
                                  ),
                                ),
                              ),
                            );
                          }
                          final attachment = state.items[index];
                          final deleting = state.deletingIds.contains(
                            attachment.id,
                          );
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.description_outlined),
                              title: Text(attachment.filename),
                              subtitle: Wrap(
                                spacing: 10,
                                children: [
                                  Text(_displayType(attachment)),
                                  Text(
                                    formatAttachmentSize(attachment.fileSize),
                                  ),
                                  Text(_formatDate(attachment.createdAt)),
                                ],
                              ),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  TextButton.icon(
                                    onPressed: () =>
                                        _download(context, ref, attachment),
                                    icon: const Icon(Icons.download_outlined),
                                    label: const Text('下载'),
                                  ),
                                  if (canManage)
                                    TextButton.icon(
                                      onPressed: deleting
                                          ? null
                                          : () => _delete(
                                              context,
                                              ref,
                                              attachment,
                                            ),
                                      icon: deleting
                                          ? const SizedBox.square(
                                              dimension: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.delete_outline),
                                      label: const Text('删除'),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadMore(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(attachmentControllerProvider(employeeId).notifier)
          .loadMore();
    } on Failure catch (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    attachment_data.EmployeeAttachment attachment,
  ) async {
    try {
      final result = await ref
          .read(attachmentControllerProvider(employeeId).notifier)
          .download(attachment);
      if (!context.mounted || result.cancelled) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('附件已保存。')));
    } on Failure catch (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('附件保存失败，请稍后重试。')));
      }
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    attachment_data.EmployeeAttachment attachment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认删除附件？'),
        content: Text('删除“${attachment.filename}”后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => dialogContext.pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => dialogContext.pop(true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await ref
          .read(attachmentControllerProvider(employeeId).notifier)
          .delete(attachment.id);
    } on Failure catch (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }
}

String formatAttachmentSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _displayType(attachment_data.EmployeeAttachment attachment) =>
    attachment.fileType.toUpperCase();

String _formatDate(DateTime date) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  final local = date.toLocal();
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)}';
}
