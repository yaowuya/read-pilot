import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../domain/search_merge.dart';
import '../components/book_cover.dart';
import '../components/common.dart';
import '../theme.dart';

/// 圆形图标按钮的底片。
const _circleFill = Color(0xFFF0F1F4);

/// 结果行右侧来源数徽章。
const _badgeFill = Color(0xFFEDEFF2);

/// 搜索页：跨书源合并后的结果 + 本地公版书库。
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.controller,
    required this.onDetails,
    required this.onSources,
    this.onBack,
  });

  final AppController controller;
  final ValueChanged<Book> onDetails;
  final VoidCallback onSources;

  /// 顶栏圆形返回按钮；为空时不渲染该按钮。
  final VoidCallback? onBack;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  static const _categories = ['全部', '文学', '诗词', '哲思'];

  final _query = TextEditingController();
  String _category = '全部';
  String _submitted = '';
  SourceExploreCategory? _activeExplore;
  List<SourceSearchGroup> _remote = [];
  bool _searching = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _cancelledSearch = false;
  bool _exactMatch = false;
  bool _shelfOnly = false;
  int _page = 0;
  int _generation = 0;
  int _processed = 0;
  int _total = 0;
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
      _processed = 0;
      _total = 0;
      _abort = query.isEmpty ? null : abort;
    });
    if (query.isEmpty) return;
    final results = await widget.controller.searchSources(
      query,
      page: page,
      abortTrigger: abort.future,
      onProgress: (processed, total) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _processed = processed;
          _total = total;
        });
      },
      // 边搜索边显示：每个书源一返回就并入结果列表。
      onResult: (group, processed, total) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _processed = processed;
          _total = total;
          _remote = loadMore
              ? _mergeResults(_remote, [group])
              : [
                  ..._remote.where((item) => item.source.id != group.source.id),
                  group,
                ];
        });
      },
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
        _processed = _total;
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
        _query.clear();
      }
      _processed = 0;
      _total = 1;
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
        _processed = _total;
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
      _processed = 0;
      _total = 0;
      _abort = null;
    });
  }

  void _retry() {
    final category = _activeExplore;
    if (category == null) {
      _search();
    } else {
      _explore(category);
    }
  }

  /// 结果胶囊文案：分类浏览只报结果数，关键词搜索再加查询进度。
  String _progressLabel(int count) {
    if (_activeExplore != null || _total <= 0) return '结果 $count';
    final done = _processed < 0
        ? 0
        : (_processed > _total ? _total : _processed);
    return '结果 $count · 进度 $done/$_total';
  }

  Future<void> _openFilters() async {
    final selection = await showModalBottomSheet<_FilterSelection>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => _FilterSheet(
        initialCategory: _category,
        initialShelfOnly: _shelfOnly,
      ),
    );
    if (selection == null || !mounted) return;
    setState(() {
      _category = selection.category;
      _shelfOnly = selection.shelfOnly;
    });
  }

  /// 跨书源合并后的结果行；精确匹配开启时只保留完全命中的书名/作者。
  List<MergedBookResult> _mergedResults() {
    if (_remote.isEmpty) return const [];
    final merged = mergeSearchResults([
      for (final group in _remote) (source: group.source, books: group.books),
    ], keyword: _activeExplore == null ? _submitted : '');
    final wanted = _submitted.trim().toLowerCase();
    if (!_exactMatch || wanted.isEmpty) return merged;
    return [
      for (final result in merged)
        if (result.primary.title.trim().toLowerCase() == wanted ||
            result.primary.author.trim().toLowerCase() == wanted)
          result,
    ];
  }

  List<Book> _catalogBooks() {
    final keyword = _submitted.trim();
    return widget.controller.catalog.where((book) {
      if (_category != '全部' && book.category != _category) return false;
      if (_shelfOnly && widget.controller.book(book.id) == null) {
        return false;
      }
      if (keyword.isEmpty) return true;
      return '${book.title}${book.author}'.contains(keyword);
    }).toList();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 650;
      final busy = _searching || _loadingMore;
      final showingRemote = _submitted.isNotEmpty || _activeExplore != null;
      final results = _mergedResults();
      final catalog = _catalogBooks();
      final failed = _remote.where((group) => group.error != null).toList();
      final explored = _activeExplore;
      return ListView(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 32,
          compact ? 10 : 24,
          compact ? 16 : 32,
          28,
        ),
        children: [
          Row(
            children: [
              if (widget.onBack != null)
                _CircleButton(
                  key: const Key('discover-back'),
                  icon: Icons.arrow_back,
                  tooltip: '返回书架',
                  onPress: widget.onBack,
                ),
              const Spacer(),
              _CircleButton(
                key: const Key('discover-sources'),
                icon: Icons.settings_outlined,
                tooltip: '管理书源',
                onPress: widget.onSources,
              ),
              const SizedBox(width: 10),
              _CircleButton(
                key: const Key('discover-exact'),
                icon: Icons.adjust,
                tooltip: _exactMatch ? '关闭精确匹配' : '精确匹配书名或作者',
                active: _exactMatch,
                onPress: () => setState(() => _exactMatch = !_exactMatch),
              ),
              const SizedBox(width: 10),
              _CircleButton(
                key: const Key('discover-filter'),
                icon: Icons.filter_alt_outlined,
                tooltip: '筛选',
                active: _category != '全部' || _shelfOnly,
                onPress: _openFilters,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Semantics(
            header: true,
            child: Text('搜索', style: Theme.of(context).textTheme.headlineLarge),
          ),
          const SizedBox(height: 18),
          _buildSearchField(),
          const SizedBox(height: 18),
          if (showingRemote)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Semantics(
                    liveRegion: true,
                    child: _ProgressChip(
                      key: const Key('discover-result-count'),
                      label: _progressLabel(results.length),
                    ),
                  ),
                ),
                if (busy)
                  TextButton(
                    key: const Key('discover-cancel'),
                    onPressed: _cancelSearch,
                    child: const Text('取消'),
                  ),
              ],
            ),
          if (showingRemote) const SizedBox(height: 14),
          if (explored != null && !_searching)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${explored.entry.title} · ${explored.source.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onSources,
                    child: const Text('管理书源'),
                  ),
                ],
              ),
            ),
          if (!showingRemote) ..._catalogResults(catalog),
          if (_submitted.isEmpty &&
              widget.controller.exploreCategories.isNotEmpty) ...[
            const SizedBox(height: 26),
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
            // 已经显示部分结果时不再压一个居中的转圈，进度胶囊足够表达状态。
            if (_searching && results.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
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
            if (!_searching && _remote.isNotEmpty && results.isEmpty)
              EmptyState(
                title: _exactMatch ? '没有完全匹配的结果' : '没有找到相关书籍',
                description: _exactMatch
                    ? '关闭精确匹配可以查看相近的书名与作者。'
                    : '换个关键词，或加载下一页看看。',
              ),
            for (final result in results)
              _ResultRow(
                book: result.primary,
                controller: widget.controller,
                inShelf: widget.controller.book(result.primary.id) != null,
                sourceCount: result.sourceCount,
                onTap: () => widget.onDetails(result.primary),
              ),
            if (failed.isNotEmpty)
              _FailedSources(groups: failed, onRetry: _retry),
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
            ..._catalogResults(catalog),
          ] else ...[
            const SizedBox(height: 14),
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

  Widget _buildSearchField() => ValueListenableBuilder<TextEditingValue>(
    valueListenable: _query,
    builder: (context, value, child) => Container(
      decoration: BoxDecoration(
        // 跟随主题的表面色，而不是单独写死的暖色。
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(30),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: TextField(
        key: const Key('discover-search'),
        controller: _query,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          hintText: '搜索书名、作者',
          hintStyle: const TextStyle(fontSize: 15, color: AppColors.muted),
          filled: false,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          prefixIcon: const Icon(Icons.search, size: 22, color: AppColors.ink),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除搜索',
                  onPressed: () {
                    _query.clear();
                    _search();
                  },
                  icon: const Icon(Icons.close, size: 20),
                ),
        ),
      ),
    ),
  );

  List<Widget> _catalogResults(List<Book> books) => [
    const SizedBox(height: 26),
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
    const SizedBox(height: 6),
    if (books.isEmpty)
      const EmptyState(
        title: '本地书库没有匹配结果',
        description: '试试其他关键词，或添加你自己的授权书源。',
      ),
    for (final book in books)
      _ResultRow(
        book: book,
        controller: widget.controller,
        inShelf: widget.controller.book(book.id) != null,
        onTap: () => widget.onDetails(book),
      ),
  ];
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPress,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPress;
  final bool active;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: active ? AppColors.ink : _circleFill,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPress,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Center(
            child: Icon(
              icon,
              size: 20,
              color: active ? Colors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    ),
  );
}

class _ProgressChip extends StatelessWidget {
  const _ProgressChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
    decoration: BoxDecoration(
      color: _circleFill,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, color: AppColors.muted),
    ),
  );
}

class _SourceCountBadge extends StatelessWidget {
  const _SourceCountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 26),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: _badgeFill,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      '$count',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.muted,
      ),
    ),
  );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.book,
    required this.controller,
    required this.inShelf,
    required this.onTap,
    this.sourceCount = 0,
  });

  final Book book;
  final AppController controller;
  final bool inShelf;
  final VoidCallback onTap;
  final int sourceCount;

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
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BookCover(
                  book: book,
                  imageLoader: controller.loadBookCover,
                  width: 72,
                  height: 101,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (sourceCount > 0) ...[
                          const SizedBox(width: 10),
                          _SourceCountBadge(
                            key: Key('result-source-count-${book.id}'),
                            count: sourceCount,
                          ),
                        ],
                      ],
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
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
}

class _FailedSources extends StatelessWidget {
  const _FailedSources({required this.groups, required this.onRetry});

  final List<SourceSearchGroup> groups;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: QuietPanel(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${groups.length} 个书源未返回结果',
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 2),
          Text(
            groups.map((group) => group.source.name).join('、'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: onRetry, child: const Text('重新搜索')),
          ),
        ],
      ),
    ),
  );
}

class _FilterSelection {
  const _FilterSelection({required this.category, required this.shelfOnly});

  final String category;
  final bool shelfOnly;
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initialCategory,
    required this.initialShelfOnly,
  });

  final String initialCategory;
  final bool initialShelfOnly;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _category = widget.initialCategory;
  late bool _shelfOnly = widget.initialShelfOnly;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('筛选', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          const Text(
            '本地书库分类',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in _DiscoverScreenState._categories)
                ChoiceChip(
                  key: ValueKey('discover-filter-$category'),
                  label: Text(category),
                  selected: _category == category,
                  showCheckmark: false,
                  selectedColor: AppColors.softBlue,
                  side: BorderSide.none,
                  onSelected: (_) => setState(() => _category = category),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            key: const Key('discover-filter-shelf-only'),
            contentPadding: EdgeInsets.zero,
            title: const Text('只看已在书架的书'),
            value: _shelfOnly,
            onChanged: (value) => setState(() => _shelfOnly = value),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('discover-filter-done'),
              onPressed: () => Navigator.of(context).pop(
                _FilterSelection(category: _category, shelfOnly: _shelfOnly),
              ),
              child: const Text('完成'),
            ),
          ),
        ],
      ),
    ),
  );
}
