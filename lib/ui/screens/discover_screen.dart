import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../components/book_cover.dart';
import '../components/common.dart';
import '../theme.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.controller,
    required this.onDetails,
    required this.onSources,
  });
  final AppController controller;
  final ValueChanged<Book> onDetails;
  final VoidCallback onSources;
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _query = TextEditingController();
  String _category = '全部';
  String _submitted = '';
  SourceExploreCategory? _activeExplore;
  List<SourceSearchGroup> _remote = [];
  bool _searching = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _cancelledSearch = false;
  int _page = 0;
  int _generation = 0;
  Completer<void>? _abort;

  @override
  void dispose() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search({bool loadMore = false}) async {
    if (loadMore && (_searching || _loadingMore || !_hasMore || _page >= 10)) {
      return;
    }
    final query = loadMore ? _submitted : _query.text.trim();
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    final generation = loadMore ? _generation : ++_generation;
    final page = loadMore ? _page + 1 : 1;
    final abort = Completer<void>();
    setState(() {
      if (loadMore) {
        _loadingMore = true;
      } else {
        _submitted = query;
        _activeExplore = null;
        _searching = query.isNotEmpty;
        _loadingMore = false;
        _cancelledSearch = false;
        _remote = [];
        _page = 0;
        _hasMore = false;
      }
      _abort = query.isEmpty ? null : abort;
    });
    if (query.isEmpty) return;
    final results = await widget.controller.searchSources(
      query,
      page: page,
      abortTrigger: abort.future,
    );
    if (mounted && generation == _generation) {
      setState(() {
        _searching = false;
        _loadingMore = false;
        _remote = loadMore ? _mergeResults(_remote, results) : results;
        _page = page;
        _hasMore =
            page < 10 &&
            results.any(
              (group) => group.error == null && group.books.isNotEmpty,
            );
        _abort = null;
      });
    }
  }

  Future<void> _explore(
    SourceExploreCategory category, {
    bool loadMore = false,
  }) async {
    if (loadMore && (_searching || _loadingMore || !_hasMore || _page >= 10)) {
      return;
    }
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    final generation = loadMore ? _generation : ++_generation;
    final page = loadMore ? _page + 1 : 1;
    final abort = Completer<void>();
    setState(() {
      if (loadMore) {
        _loadingMore = true;
      } else {
        _submitted = '';
        _activeExplore = category;
        _searching = true;
        _cancelledSearch = false;
        _remote = [];
        _page = 0;
        _hasMore = false;
      }
      _abort = abort;
    });
    final result = await widget.controller.exploreSource(
      category,
      page: page,
      abortTrigger: abort.future,
    );
    if (mounted && generation == _generation) {
      setState(() {
        _searching = false;
        _loadingMore = false;
        final results = [result];
        _remote = loadMore ? _mergeResults(_remote, results) : results;
        _page = page;
        _hasMore = page < 10 && result.error == null && result.books.isNotEmpty;
        _abort = null;
      });
    }
  }

  void _loadMore() {
    final category = _activeExplore;
    if (category == null) {
      _search(loadMore: true);
    } else {
      _explore(category, loadMore: true);
    }
  }

  List<SourceSearchGroup> _mergeResults(
    List<SourceSearchGroup> current,
    List<SourceSearchGroup> next,
  ) {
    final merged = {for (final group in current) group.source.id: group};
    for (final group in next) {
      final existing = merged[group.source.id];
      if (existing == null) {
        merged[group.source.id] = group;
        continue;
      }
      final books = {
        for (final book in existing.books) book.id: book,
        for (final book in group.books) book.id: book,
      }.values.toList();
      merged[group.source.id] = SourceSearchGroup(
        group.source,
        books,
        error: books.isEmpty ? group.error ?? existing.error : null,
      );
    }
    return merged.values.toList();
  }

  void _cancelSearch() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    _generation++;
    setState(() {
      _searching = false;
      _loadingMore = false;
      _cancelledSearch = true;
      _abort = null;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 650;
      final busy = _searching || _loadingMore;
      final showingRemote = _submitted.isNotEmpty || _activeExplore != null;
      final resultCount = _remote
          .where((group) => group.error == null)
          .fold(0, (total, group) => total + group.books.length);
      final sourceCount = _remote
          .map((group) => group.source.id)
          .toSet()
          .length;
      final books = widget.controller.catalog
          .where(
            (book) =>
                (_category == '全部' || book.category == _category) &&
                '${book.title}${book.author}'.contains(_submitted),
          )
          .toList();
      return ListView(
        padding: EdgeInsets.all(compact ? 16 : 32),
        children: [
          Semantics(
            header: true,
            child: Text(
              '搜索',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _query,
                  builder: (context, value, child) => TextField(
                    key: const Key('discover-search'),
                    controller: _query,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: '搜索书名、作者',
                      prefixIcon: const Icon(Icons.search, size: 21),
                      isDense: true,
                      suffixIcon: value.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清除搜索',
                              onPressed: () {
                                _query.clear();
                                _search();
                              },
                              icon: const Icon(Icons.close, size: 18),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: busy ? _cancelSearch : _search,
                child: Text(busy ? '取消' : '搜索'),
              ),
            ],
          ),
          if (!showingRemote) ..._catalogResults(books),
          if (_submitted.isEmpty &&
              widget.controller.exploreCategories.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('书源发现', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in widget.controller.exploreCategories)
                  ActionChip(
                    key: ValueKey('discover-explore-${category.id}'),
                    label: Text(category.entry.title),
                    tooltip: category.source.name,
                    onPressed: busy ? null : () => _explore(category),
                  ),
              ],
            ),
          ],
          if (showingRemote) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _activeExplore == null
                        ? '搜索结果'
                        : '${_activeExplore!.entry.title} · '
                              '${_activeExplore!.source.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: widget.onSources,
                  child: const Text('管理书源'),
                ),
              ],
            ),
            Semantics(
              liveRegion: true,
              child: Text(
                _searching
                    ? '正在搜索书源…'
                    : '网络结果 $resultCount · 已查 $sourceCount 个书源',
                key: const Key('discover-result-count'),
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 12),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_searching && _remote.isEmpty)
              EmptyState(
                title: _cancelledSearch
                    ? '已取消搜索。'
                    : _activeExplore == null
                    ? '还没有启用的网络书源'
                    : '这个分类暂时没有书籍',
                description: _cancelledSearch
                    ? '可以调整关键词后重新搜索。'
                    : _activeExplore == null
                    ? '在“书源”中导入你有权访问的书库配置，再来搜索。'
                    : '可以稍后重试，或选择其他书源分类。',
              ),
            for (final group in _remote) ...[
              if (group.error != null || group.books.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 10),
                  child: Text(
                    group.source.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              if (group.error != null)
                QuietPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.error!,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      TextButton(
                        onPressed: () {
                          final category = _activeExplore;
                          if (category == null) {
                            _search();
                          } else {
                            _explore(category);
                          }
                        },
                        child: const Text('重新搜索'),
                      ),
                    ],
                  ),
                )
              else if (group.books.isEmpty)
                const QuietPanel(
                  child: Text(
                    '这个书源没有找到相关书籍。',
                    style: TextStyle(color: AppColors.muted),
                  ),
                )
              else
                for (final book in group.books)
                  _BookResult(
                    book: book,
                    controller: widget.controller,
                    inShelf: widget.controller.book(book.id) != null,
                    onTap: () => widget.onDetails(book),
                  ),
            ],
            if (_remote.isNotEmpty && (_hasMore || _loadingMore))
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Center(
                  child: OutlinedButton(
                    key: const Key('discover-load-more'),
                    onPressed: _loadingMore ? _cancelSearch : _loadMore,
                    child: Text(
                      _loadingMore ? '取消加载' : '加载下一页（${_page + 1}/10）',
                    ),
                  ),
                ),
              ),
            ..._catalogResults(books),
          ] else ...[
            const SizedBox(height: 12),
            QuietPanel(
              child: Row(
                children: [
                  const Icon(Icons.language_outlined, color: AppColors.muted),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      '自己的书源，自己的阅读世界。\n支持声明式 CSS 书源导入。',
                      style: TextStyle(height: 1.8, color: AppColors.muted),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onSources,
                    child: const Text('去添加'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      );
    },
  );

  List<Widget> _catalogResults(List<Book> books) => [
    const SizedBox(height: 24),
    Wrap(
      spacing: 8,
      children: [
        for (final category in ['全部', '文学', '诗词', '哲思'])
          ChoiceChip(
            label: Text(category),
            selected: _category == category,
            showCheckmark: false,
            selectedColor: const Color(0xFFE8EBEF),
            side: BorderSide.none,
            onSelected: (_) => setState(() => _category = category),
          ),
      ],
    ),
    const SizedBox(height: 16),
    Row(
      children: [
        Expanded(
          child: Text(
            _submitted.isEmpty ? '值得重读的经典' : '本地结果 ${books.length}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const Text(
          '公版 · 离线可读',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    ),
    const SizedBox(height: 8),
    if (books.isEmpty)
      const EmptyState(
        title: '本地书库没有匹配结果',
        description: '试试其他关键词，或添加你自己的授权书源。',
      ),
    for (final book in books)
      _BookResult(
        book: book,
        controller: widget.controller,
        inShelf: widget.controller.book(book.id) != null,
        onTap: () => widget.onDetails(book),
      ),
  ];
}

class _BookResult extends StatelessWidget {
  const _BookResult({
    required this.book,
    required this.controller,
    required this.inShelf,
    required this.onTap,
  });
  final Book book;
  final AppController controller;
  final bool inShelf;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCover(
              book: book,
              imageLoader: controller.loadBookCover,
              width: 64,
              height: 92,
            ),
            const SizedBox(width: 14),
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
                  const SizedBox(height: 4),
                  Text(
                    [
                      book.author,
                      book.category,
                    ].where((value) => value.trim().isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '来源：${book.sourceLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                  if (book.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      book.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                  if (inShelf) ...[
                    const SizedBox(height: 6),
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
