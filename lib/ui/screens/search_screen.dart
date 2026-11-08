import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../domain/book_source.dart';
import '../../domain/search_merge.dart';
import '../components/book_cover.dart';
import '../components/design.dart';
import '../theme.dart';

/// 搜索：按设计稿从发现页的搜索框进入，整页呈现历史、条件与结果。
///
/// 检索本身沿用 `controller.searchSources`：并发查询所有启用的书源、边出结果边
/// 合并同名书。本页只负责把结果按稿排版，并在提交时把关键词写入本机历史。
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.controller,
    required this.onDetails,
    required this.onOpen,
    this.initialQuery = '',
    this.source,
  });

  final AppController controller;
  final ValueChanged<Book> onDetails;
  final void Function(Book book) onOpen;
  final String initialQuery;

  /// 限定在这一个书源里搜索；为空时搜全部已启用书源。
  final BookSource? source;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  String _submitted = '';
  List<SourceSearchGroup> _remote = [];
  bool _searching = false;
  int _generation = 0;
  Completer<void>? _abort;
  List<String> _history = const [];

  @override
  void initState() {
    super.initState();
    _query.text = widget.initialQuery;
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final items = await widget.controller.searchHistory();
    if (!mounted) return;
    setState(() => _history = items);
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
    unawaited(_remember(keyword));
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

  Future<void> _remember(String keyword) async {
    await widget.controller.rememberSearch(keyword);
    final items = await widget.controller.searchHistory();
    if (mounted) setState(() => _history = items);
  }

  Future<void> _clearHistory() async {
    await widget.controller.clearSearchHistory();
    if (mounted) setState(() => _history = const []);
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
    final focused = widget.source;
    final results = mergeSearchResults([
      for (final group in _remote) (source: group.source, books: group.books),
    ], keyword: _submitted);
    final scoped = focused == null
        ? results
        : [
            for (final result in results)
              if (result.sources.any((source) => source.id == focused.id))
                result,
          ];
    final failed = _remote.where((group) => group.error != null).length;
    final enabled = widget.controller.sources
        .where((source) => source.enabled)
        .length;

    return Scaffold(
      appBar: AppTopBar(
        onBack: () => Navigator.of(context).maybePop(),
        title: '搜索',
        actions: [
          CircleIconButton(
            key: const Key('search-scope'),
            icon: Icons.tune,
            tooltip: focused == null ? '全部书源' : focused.name,
            onPressed: () => _showScope(context),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: SearchPill(
                    controller: _query,
                    autofocus: widget.initialQuery.isEmpty,
                    hintText: '搜索书名、作者',
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 42,
                  child: FilledButton(
                    key: const Key('search-submit'),
                    onPressed: _searching ? _cancel : _search,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: Text(_searching ? '取消' : '搜索'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 20, 0),
            child: Text(
              focused == null
                  ? '在 $enabled 个已启用书源中查找'
                  : '只在「${focused.name}」中查找',
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: _body(
              scoped: scoped,
              failed: failed,
              focusRing: focused,
              enabled: enabled,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body({
    required List<MergedBookResult> scoped,
    required int failed,
    required BookSource? focusRing,
    required int enabled,
  }) {
    if (_searching && _remote.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_submitted.isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        children: [
          Text(
            failed == 0
                ? '找到 ${scoped.length} 本'
                : '找到 ${scoped.length} 本 · $failed 个书源未返回结果',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          if (scoped.isEmpty)
            const EmptyBlock(
              icon: Icons.search_off,
              title: '没有找到相关书籍',
              description: '换个关键词，或换一条书源再试。',
              compact: true,
            ),
          for (final result in scoped)
            _ResultRow(
              key: ValueKey('search-result-${result.primary.id}'),
              book: result.primary,
              controller: widget.controller,
              sourceCount: result.sourceCount,
              inShelf: widget.controller.book(result.primary.id) != null,
              onDetails: () => widget.onDetails(result.primary),
            ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      children: [
        if (_history.isNotEmpty) ...[
          SectionLabel(
            '搜索历史',
            trailing: TextButton(
              key: const Key('search-history-clear'),
              onPressed: _clearHistory,
              child: const Text('清空'),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final keyword in _history)
                ActionChip(
                  key: ValueKey('search-history-$keyword'),
                  label: Text(keyword),
                  labelStyle: const TextStyle(fontSize: 12),
                  backgroundColor: const Color(0xFFF4F5F7),
                  side: BorderSide.none,
                  onPressed: () {
                    _query.text = keyword;
                    unawaited(_search());
                  },
                ),
            ],
          ),
          const SizedBox(height: 30),
        ],
        const Center(
          child: Icon(
            Icons.auto_stories_outlined,
            size: 34,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            '从一本想读的书开始',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 10),
        const Center(
          child: Text(
            '输入书名或作者，点击搜索。',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            enabled == 0 ? '还没有启用的书源，先在书源管理里添加。' : '在 $enabled 个已启用书源中查找。',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ),
      ],
    );
  }

  void _showScope(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          ListTile(
            key: const Key('search-scope-all'),
            title: const Text('全部书源'),
            selected: widget.source == null,
            onTap: () => Navigator.of(sheetContext).pop(),
          ),
        ],
      ),
    ),
  );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    super.key,
    required this.book,
    required this.controller,
    required this.sourceCount,
    required this.inShelf,
    required this.onDetails,
  });

  final Book book;
  final AppController controller;
  final int sourceCount;
  final bool inShelf;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final meta = [
      book.author,
      book.category,
    ].where((value) => value.trim().isNotEmpty).join(' · ');
    return InkWell(
      onTap: onDetails,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: BookCover(
                book: book,
                imageLoader: controller.loadBookCover,
                width: 56,
                height: 78,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (sourceCount > 1) PillTag('$sourceCount 个来源'),
                      if (inShelf) const PillTag('已在书架', tone: PillTone.blue),
                      if (book.chapters.isNotEmpty)
                        PillTag('${book.chapters.length} 章'),
                    ],
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
