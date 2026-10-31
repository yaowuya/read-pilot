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
      _abort = null;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 650;
      final busy = _searching || _loadingMore;
      final books = widget.controller.catalog
          .where(
            (book) =>
                (_category == '全部' || book.category == _category) &&
                '${book.title}${book.author}'.contains(_submitted),
          )
          .toList();
      return ListView(
        padding: EdgeInsets.all(compact ? 20 : 40),
        children: [
          const PageHeading(title: '发现好书', subtitle: '在字里行间，遇见更大的世界。'),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('discover-search'),
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    hintText: '找一本书，也找一种心境',
                    prefixIcon: Icon(Icons.search, size: 21),
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
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
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
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                _submitted.isEmpty ? '值得重读的经典' : '本地书库',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              const Text(
                '公版 · 离线可读',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '原文节选，慢慢读。不需要账号，也不需要网络。',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          if (books.isEmpty)
            const EmptyState(
              title: '本地书库没有匹配结果',
              description: '试试其他关键词，或添加你自己的授权书源。',
            ),
          for (final book in books)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _BookResult(
                book: book,
                controller: widget.controller,
                inShelf: widget.controller.book(book.id) != null,
                onTap: () => widget.onDetails(book),
              ),
            ),
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
          if (_submitted.isNotEmpty || _activeExplore != null) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  _activeExplore == null
                      ? '我的书源'
                      : '${_activeExplore!.entry.title} · '
                            '${_activeExplore!.source.name}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                TextButton(
                  onPressed: widget.onSources,
                  child: const Text('管理书源'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_searching && _remote.isEmpty)
              EmptyState(
                title: _activeExplore == null ? '还没有启用的网络书源' : '这个分类暂时没有书籍',
                description: _activeExplore == null
                    ? '在“书源”中导入你有权访问的书库配置，再来搜索。'
                    : '可以稍后重试，或选择其他书源分类。',
              ),
            for (final group in _remote) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 14),
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _BookResult(
                      book: book,
                      controller: widget.controller,
                      inShelf: widget.controller.book(book.id) != null,
                      onTap: () => widget.onDetails(book),
                    ),
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
  Widget build(BuildContext context) => QuietPanel(
    padding: const EdgeInsets.all(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BookCover(
            book: book,
            imageLoader: controller.loadBookCover,
            width: 78,
            height: 110,
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${book.author} · ${book.category}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 10),
                Text(
                  book.description.isEmpty
                      ? '来自 ${book.sourceLabel}'
                      : book.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.7,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  inShelf ? '已在书架' : '查看这本书  →',
                  style: TextStyle(
                    fontSize: 12,
                    color: inShelf ? AppColors.muted : AppColors.blue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
