import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../../authentication/presentation/auth_session_store.dart';
import '../data/audit_event.dart';
import '../data/audit_export_repository.dart';
import '../data/audit_repository.dart';
import 'audit_export_controller.dart';

final auditPageProvider = FutureProvider.autoDispose<AuditEventPage>(
  (ref) => ref.watch(auditRepositoryProvider).fetchAuditEvents(),
  retry: (retryCount, error) => null,
);

class AuditPage extends ConsumerStatefulWidget {
  const AuditPage({super.key});

  @override
  ConsumerState<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends ConsumerState<AuditPage> {
  static const filters = AuditExportFilters();
  bool exporting = false;

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(auditPageProvider);
    final canExport = ref
        .watch(authSessionStoreProvider)
        .capabilities
        .canExportAudit;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '审计日志',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 4),
                      const Text('只读查看目录、账号和会话的安全操作记录。'),
                    ],
                  ),
                ),
                if (canExport)
                  FilledButton.tonalIcon(
                    key: const Key('audit_export'),
                    onPressed: exporting ? null : _confirmAndExport,
                    icon: const Icon(Icons.download_outlined),
                    label: Text(exporting ? '正在导出' : '导出 CSV'),
                  ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const Key('audit_refresh'),
                  tooltip: '刷新审计日志',
                  onPressed: () => ref.invalidate(auditPageProvider),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: events.when(
                loading: () => const AppLoadingView(label: '正在加载审计日志'),
                error: (error, _) => AppErrorView(
                  message: error is Failure ? error.message : '审计日志加载失败，请稍后重试。',
                  onRetry: () => ref.invalidate(auditPageProvider),
                ),
                data: (page) => page.results.isEmpty
                    ? const Center(child: Text('暂无审计事件'))
                    : ListView.separated(
                        itemCount: page.results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _AuditEventCard(event: page.results[index]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndExport() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认导出审计？'),
        content: Text('筛选范围：${filters.summary}\n最多导出服务器允许的记录数量。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认导出'),
          ),
        ],
      ),
    );
    if (confirmed != true || exporting) return;
    setState(() => exporting = true);
    try {
      final result = await ref
          .read(auditExportControllerProvider)
          .export(filters);
      if (!mounted) return;
      final message = result.cancelled ? '已取消保存。' : '审计文件已保存：${result.path}';
      _showMessage(message);
    } on Failure catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AuditEventCard extends StatelessWidget {
  const _AuditEventCard({required this.event});

  final AuditEvent event;

  @override
  Widget build(BuildContext context) {
    final summary = event.changes.entries
        .map((entry) => '${entry.key}: ${_safeChangeValue(entry.value)}')
        .join('；');
    return Card(
      child: ListTile(
        leading: const Icon(Icons.policy_outlined),
        title: Text('${event.action} · ${event.resourceLabel}'),
        subtitle: Text(
          '${event.actorUsername ?? '系统'} · ${event.source}'
          '${summary.isEmpty ? '' : '\n$summary'}',
        ),
        isThreeLine: summary.isNotEmpty,
        trailing: Text(_formatTimestamp(event.createdAt)),
      ),
    );
  }
}

String _safeChangeValue(Object? value) {
  if (value case {'from': final Object? from, 'to': final Object? to}) {
    return '${from ?? '空'} → ${to ?? '空'}';
  }
  return '已变更';
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.month}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
