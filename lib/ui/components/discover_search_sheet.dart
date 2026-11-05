import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../domain/book_source.dart';
import '../../domain/search_merge.dart';
import '../components/book_cover.dart';
import '../components/common.dart';
import '../theme.dart';

/// 发现页的搜索面板：跨书源搜索，合并同书名的结果。
///
/// legado 的发现页顶栏有一个搜索入口，搜索作用域是当前选中的书源；这里做成
/// 一个半屏面板，避免把发现页本身变回搜索页。
class DiscoverSearchSheet extends StatefulWidget {
  const DiscoverSearchSheet({super.key, required this.controller, this.source});

  final AppController controller;

  /// 限定搜索这一个书源；为空时搜索所有已启用的书源。
  final BookSource? source;

  @override
  State<DiscoverSearchSheet> createState() => _DiscoverSearchSheetState();
}

class _DiscoverSearchSheetState extends State<DiscoverSearchSheet> {
  final _query = TextEditingController();
  String _submitted = '';
  List<SourceSearchGroup> _remote = [];
  bool _searching = false;
  int _generation = 0;
  Completer<void>? _abort;

  @override
  void dispose() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _query.text.trim();
    if (keyword.isEmpty) return;
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    final generation = ++_generation;
    final abort = Completer<void>();
    setState(() {
      _submitted = keyword;
      _searching = true;
      _remote = [];
      _abort = abort;
    });
    final groups = await widget.controller.searchSources(
      keyword,
      abortTrigger: abort.future,
      onResult: (group, processed, total) {
        if (!mounted || generation != _generation) return;
        setState(() => _remote = [..._remote, group]);
      },
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _searching = false;
      _remote = groups;
      _abort = null;
    });
  }

  void _cancel() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    _generation++;
    setState(() {
      _searching = false;
      _abort = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = mergeSearchResults([
      for (final group in _remote) (source: group.source, books: group.books),
    ], keyword: _submitted);
    final focused = widget.source;
    final scoped = focused == null
        ? results
        : [
            for (final result in results)
              if (result.sources.any((source) => source.id == focused.id))
                result,
          ];
    final failed = _remote.where((group) => group.error != null).length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    focused == null ? '搜索全部书源' : '在“${focused.name}”中搜索',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (_searching)
                  TextButton(
                    key: const Key('discover-search-cancel'),
                    onPressed: _cancel,
                    child: const Text('取消'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(26),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const Key('discover-search-field'),
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                  hintText: '搜索书名、作者',
                  prefixIcon: Icon(Icons.search, size: 20),
                  prefixIconConstraints: BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_searching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_searching && _submitted.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  failed == 0
                      ? '找到 ${scoped.length} 本'
                      : '找到 ${scoped.length} 本 · $failed 个书源未返回结果',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            if (!_searching && _submitted.isNotEmpty && scoped.isEmpty)
              const EmptyState(
                title: '没有找到相关书籍',
                description: '换个关键词，或换一条书源再试。',
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final result in scoped)
                    _SearchRow(
                      key: ValueKey(
                        'discover-search-result-${result.primary.id}',
                      ),
                      book: result.primary,
                      controller: widget.controller,
                      sourceCount: result.sourceCount,
                      inShelf:
                          widget.controller.book(result.primary.id) != null,
                      onTap: () => Navigator.of(context).pop([result.primary]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    super.key,
    required this.book,
    required this.controller,
    required this.sourceCount,
    required this.inShelf,
    required this.onTap,
  });

  final Book book;
  final AppController controller;
  final int sourceCount;
  final bool inShelf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = [
      book.author,
      book.category,
    ].where((value) => value.trim().isNotEmpty).join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BookCover(
                  book: book,
                  imageLoader: controller.loadBookCover,
                  width: 60,
                  height: 84,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                    if (sourceCount > 1) ...[
                      const SizedBox(height: 5),
                      Text(
                        '$sourceCount 个书源有这本书',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                    if (inShelf) ...[
                      const SizedBox(height: 5),
                      const Text(
                        '已在书架',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
