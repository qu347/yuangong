import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import 'attachment_page.dart';
import 'attachment_upload_controller.dart';

class AttachmentUploadPage extends ConsumerWidget {
  const AttachmentUploadPage({required this.employeeId, super.key});

  final String employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upload = ref.watch(attachmentUploadControllerProvider(employeeId));

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '返回员工附件',
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/employees/$employeeId/attachments');
                        }
                      },
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '上传员工附件',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: upload.when(
                      loading: () => const AppLoadingView(label: '正在准备上传'),
                      error: (error, _) => AppErrorView(
                        message: error is Failure
                            ? error.message
                            : '上传页面加载失败，请稍后重试。',
                        onRetry: () => ref.invalidate(
                          attachmentUploadControllerProvider(employeeId),
                        ),
                      ),
                      data: (state) {
                        final candidate = state.candidate;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '允许 PDF、DOCX、XLSX、JPG、JPEG、PNG，单个文件不超过 10 MiB。',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 20),
                            OutlinedButton.icon(
                              onPressed: state.isUploading || state.isChoosing
                                  ? null
                                  : () => ref
                                        .read(
                                          attachmentUploadControllerProvider(
                                            employeeId,
                                          ).notifier,
                                        )
                                        .chooseFile(),
                              icon: const Icon(Icons.attach_file),
                              label: Text(state.isChoosing ? '正在选择' : '选择文件'),
                            ),
                            if (candidate != null) ...[
                              const SizedBox(height: 20),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        candidate.name,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 10,
                                        children: [
                                          Text(
                                            candidate.extension.toUpperCase(),
                                          ),
                                          Text(
                                            formatAttachmentSize(
                                              candidate.size,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (state.failure != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                state.failure!.message,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed:
                                  candidate == null ||
                                      state.isChoosing ||
                                      state.isUploading
                                  ? null
                                  : () => _submit(context, ref),
                              icon: state.isUploading
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.cloud_upload_outlined),
                              label: Text(state.isUploading ? '正在上传' : '上传'),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    final succeeded = await ref
        .read(attachmentUploadControllerProvider(employeeId).notifier)
        .submit();
    if (!succeeded || !context.mounted) {
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/employees/$employeeId/attachments');
    }
  }
}
