import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_loading_view.dart';
import '../data/global_search_repository.dart';
import 'global_search_controller.dart';

class GlobalSearchPage extends ConsumerStatefulWidget {
  const GlobalSearchPage({super.key});

  @override
  ConsumerState<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends ConsumerState<GlobalSearchPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(globalSearchControllerProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('全局搜索', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            SearchBar(
              controller: _controller,
              hintText: '搜索姓名、工号、邮箱、部门或岗位',
              leading: const Icon(Icons.search),
              trailing: [
                IconButton(
                  tooltip: '搜索',
                  onPressed: () => ref
                      .read(globalSearchControllerProvider.notifier)
                      .search(_controller.text),
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ],
              onSubmitted: (value) => ref
                  .read(globalSearchControllerProvider.notifier)
                  .search(value),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: results.when(
                loading: () =>
                    const Center(child: AppLoadingView(label: '正在搜索')),
                error: (error, _) => Center(
                  child: AppErrorView(
                    message: error is Failure ? error.message : '搜索失败，请稍后重试。',
                    onRetry: () => ref
                        .read(globalSearchControllerProvider.notifier)
                        .retry(),
                  ),
                ),
                data: (page) {
                  if (page == null) {
                    return const Center(child: Text('输入关键词开始搜索'));
                  }
                  if (page.results.isEmpty) {
                    return const Center(child: Text('没有找到匹配结果'));
                  }
                  final groups = [
                    _SearchResultGroup(
                      type: SearchResultType.employee,
                      label: '员工',
                      items: page.results
                          .where(
                            (item) => item.type == SearchResultType.employee,
                          )
                          .toList(growable: false),
                    ),
                    _SearchResultGroup(
                      type: SearchResultType.department,
                      label: '部门',
                      items: page.results
                          .where(
                            (item) => item.type == SearchResultType.department,
                          )
                          .toList(growable: false),
                    ),
                    _SearchResultGroup(
                      type: SearchResultType.position,
                      label: '岗位',
                      items: page.results
                          .where(
                            (item) => item.type == SearchResultType.position,
                          )
                          .toList(growable: false),
                    ),
                  ];
                  return ListView(
                    children: [
                      for (final group in groups)
                        if (group.items.isNotEmpty) ...[
                          _GroupHeader(group: group),
                          const SizedBox(height: 8),
                          for (final item in group.items) ...[
                            _ResultCard(item: item),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 8),
                        ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultGroup {
  const _SearchResultGroup({
    required this.type,
    required this.label,
    required this.items,
  });

  final SearchResultType type;
  final String label;
  final List<GlobalSearchResult> items;
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final _SearchResultGroup group;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          _iconFor(group.type),
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(group.label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 8),
        Badge(label: Text('${group.items.length}')),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.item});

  final GlobalSearchResult item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(item.title),
        subtitle: Text(item.subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => item.type == SearchResultType.employee
            ? context.go('/employees/${item.id}')
            : context.go('/departments'),
      ),
    );
  }
}

IconData _iconFor(SearchResultType type) => switch (type) {
  SearchResultType.employee => Icons.person_outline,
  SearchResultType.department => Icons.account_tree_outlined,
  SearchResultType.position => Icons.work_outline,
};
