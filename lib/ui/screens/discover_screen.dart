import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../domain/book_source.dart';
import '../../domain/explore_kind.dart';
import '../components/book_cover.dart';
import '../components/common.dart';
import '../components/explore_kind_row.dart';
import '../components/discover_search_sheet.dart';
import '../theme.dart';

/// 圆形图标按钮的底片。
const _circleFill = Color(0xFFF0F1F4);

/// 一页发现书籍列表最多展示多少本，和 legado 的榜单首页一致。
const _pageBookLimit = 60;

/// 发现页，对齐 legado 的发现页。
///
/// 两种模式，由右上角的切换按钮切换，并且记住用户上次的选择：
///  * 浏览模式（[ExploreMode.browse]）：一条书源一节，每节里排开它自己声明的
///    发现分类；上下滚动就能逛完所有书源，点分类进入该分类的书籍列表。
///  * 内容模式（[ExploreMode.content]）：一次只看一条书源，顶部是分类标签栏
///    加横向翻页，切书源时保留各自上次看的分页。
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.controller,
    required this.onDetails,
    required this.onSources,
    this.onOpen,
    this.onBack,
  });

  final AppController controller;
  final ValueChanged<Book> onDetails;
  final VoidCallback onSources;

  /// Opens a search hit straight into the reader; falling back to book details
  /// would add a step the discover list never needed.
  final ValueChanged<Book>? onOpen;
  final VoidCallback? onBack;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

enum ExploreMode { browse, content }

class _DiscoverScreenState extends State<DiscoverScreen> {
  ExploreMainSelection _selection = const ExploreMainSelection();
  ExploreMode _mode = ExploreMode.browse;
  String? _group;

  /// 每条书源的发现分类；脚本生成的分类会有 [ExploreKindSet.unsupportedReason]。
  final _kindsBySource = <String, ExploreKindSet>{};
  final _infoBySource = <String, Map<String, String>>{};

  /// 当前打开的分类列表（浏览模式点分类、内容模式下也用它）。
  _ExplorePage? _page;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSelection());
  }

  @override
  void dispose() {
    if (!(_page?.abort.isCompleted ?? true)) _page!.abort.complete();
    super.dispose();
  }

  Future<void> _loadSelection() async {
    final selection = await widget.controller.exploreSelection();
    final info = <String, Map<String, String>>{};
    for (final source in widget.controller.exploreSources) {
      info[source.id] = await widget.controller.sourceExploreInfo(source.id);
    }
    if (!mounted) return;
    setState(() {
      _selection = selection;
      _mode = selection.showContent ? ExploreMode.content : ExploreMode.browse;
      _infoBySource.addAll(info);
      _computeKinds();
    });
  }

  void _computeKinds() {
    _kindsBySource.clear();
    for (final source in widget.controller.exploreSources) {
      _kindsBySource[source.id] = source.exploreKindSet;
    }
  }

  Future<void> _persistSelection(ExploreMainSelection next) async {
    setState(() => _selection = next);
    await widget.controller.saveExploreSelection(next);
  }

  Future<void> _setMode(ExploreMode mode) async {
    setState(() => _mode = mode);
    await _persistSelection(
      _selection.withShowContent(mode == ExploreMode.content),
    );
  }

  Future<void> _setSource(String sourceUrl) async {
    setState(() => _selection = _selection.withSource(sourceUrl));
    await widget.controller.saveExploreSelection(_selection);
    final source = _sourceFor(sourceUrl);
    if (source == null) return;
    final kinds = _kindsBySource[source.id] ?? const ExploreKindSet.empty();
    final loadable = loadableExploreKinds(kinds.kinds);
    if (loadable.isEmpty) {
      setState(() => _page = null);
      return;
    }
    final saved = _selection.kindKeyFor(source.id);
    final kind = loadable.firstWhere(
      (item) => item.key == saved,
      orElse: () => loadable.first,
    );
    await _openKind(source, kind, keepMode: true);
  }

  Future<void> _setKind(String sourceUrl, ExploreKind kind) async {
    await _persistSelection(_selection.withKind(sourceUrl, kind.key));
    final source = _sourceFor(sourceUrl);
    if (source == null) return;
    await _openKind(source, kind, keepMode: true);
  }

  BookSource? _sourceFor(String? url) {
    for (final source in widget.controller.exploreSources) {
      if (source.id == url) return source;
    }
    return null;
  }

  Future<void> _onKindValue(
    BookSource source,
    ExploreKind kind,
    String value,
  ) async {
    final values = Map<String, String>.from(
      _infoBySource[source.id] ?? const {},
    );
    values[kind.title] = value;
    setState(() => _infoBySource[source.id] = values);
    await widget.controller.saveSourceExploreInfo(source.id, values);
    // 只改取值不自动发请求：legado 也是点分类时才带上当前取值。
    if (kind.type == ExploreKindType.select ||
        kind.type == ExploreKindType.toggle) {
      final page = _page;
      if (page != null &&
          page.source.id == source.id &&
          page.kind.title == kind.title) {
        await _loadPage(page, page.page);
      }
    }
  }

  Future<void> _onKindButton(BookSource source, ExploreKind kind) async {
    if (kind.isError) {
      showMessage(context, '这条书源的发现分类规则解析失败。');
      return;
    }
    // legado 的 button 类执行书源声明的动作；当前运行时没有脚本能力，
    // 因此明确告诉用户这条分类需要在支持脚本的客户端里执行。
    showMessage(context, '“${kind.title}”需要在支持脚本的书源客户端里执行。');
  }

  Future<void> _openKind(
    BookSource source,
    ExploreKind kind, {
    bool keepMode = false,
  }) async {
    if (!(_page?.abort.isCompleted ?? true)) _page!.abort.complete();
    final page = _ExplorePage(source: source, kind: kind);
    setState(() => _page = page);
    await _loadPage(page, 1);
  }

  Future<void> _loadPage(_ExplorePage page, int number) async {
    if (page.loading && number == page.page) return;
    final generation = page.generation;
    setState(() {
      page.loading = true;
      page.error = null;
      page.page = number;
    });
    final previous = page.abort;
    page.abort = Completer<void>();
    if (!previous.isCompleted) previous.complete();
    final group = await widget.controller.exploreKind(
      page.source,
      page.kind,
      page: number,
      abortTrigger: page.abort.future,
    );
    if (!mounted || page.generation != generation) return;
    setState(() {
      page.loading = false;
      page.error = group.error;
      page.books = number == 1
          ? group.books
          : [
              ...page.books,
              for (final book in group.books)
                if (!page.books.any((item) => item.id == book.id)) book,
            ];
      page.hasMore = group.error == null && group.books.isNotEmpty;
    });
  }

  Future<void> _closePage() async {
    if (!(_page?.abort.isCompleted ?? true)) _page!.abort.complete();
    setState(() => _page = null);
  }

  Future<void> _openSearch() async {
    final source = _sourceFor(_selection.sourceUrl);
    final books = await showModalBottomSheet<List<Book>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) =>
          DiscoverSearchSheet(controller: widget.controller, source: source),
    );
    if (books == null || !mounted) return;
    for (final book in books) {
      widget.onDetails(book);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 650;
      final page = _page;
      final sources = widget.controller.exploreSourcesInGroup(_group);
      final showingPage = page != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 32,
              compact ? 10 : 24,
              compact ? 16 : 32,
              0,
            ),
            child: _buildHeader(showingPage, compact),
          ),
          if (!showingPage) _buildControls(sources, compact),
          Expanded(
            child: showingPage
                ? _buildPage(page, compact)
                : _buildBrowse(sources, compact),
          ),
        ],
      );
    },
  );

  Widget _buildHeader(bool showingPage, bool compact) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          if (showingPage)
            _CircleButton(
              key: const Key('discover-page-back'),
              icon: Icons.arrow_back,
              tooltip: '返回发现',
              onPress: _closePage,
            )
          else if (widget.onBack != null)
            _CircleButton(
              key: const Key('discover-back'),
              icon: Icons.arrow_back,
              tooltip: '返回书架',
              onPress: widget.onBack,
            ),
          const Spacer(),
          _CircleButton(
            key: const Key('discover-search'),
            icon: Icons.search,
            tooltip: '搜索书籍',
            onPress: _openSearch,
          ),
          const SizedBox(width: 10),
          _CircleButton(
            key: const Key('discover-mode'),
            icon: _mode == ExploreMode.content
                ? Icons.view_carousel_outlined
                : Icons.view_day_outlined,
            tooltip: _mode == ExploreMode.content ? '切换到书源列表' : '切换到分类浏览',
            onPress: () => _setMode(
              _mode == ExploreMode.content
                  ? ExploreMode.browse
                  : ExploreMode.content,
            ),
          ),
          const SizedBox(width: 10),
          _CircleButton(
            key: const Key('discover-sources'),
            icon: Icons.settings_outlined,
            tooltip: '管理书源',
            onPress: widget.onSources,
          ),
        ],
      ),
      const SizedBox(height: 14),
      Semantics(
        header: true,
        child: Text('发现', style: Theme.of(context).textTheme.headlineLarge),
      ),
      const SizedBox(height: 6),
      Text(
        _subtitle(showingPage),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: AppColors.muted),
      ),
    ],
  );

  String _subtitle(bool showingPage) {
    final page = _page;
    if (showingPage && page != null) {
      return '${page.source.name} · ${page.kind.title}';
    }
    final group = _group;
    if (group != null && group.isNotEmpty) return '分组：$group';
    final sources = widget.controller.exploreSources;
    return sources.isEmpty
        ? '还没有启用的发现书源'
        : '${sources.length} 个书源，${widget.controller.sourceGroups.length} 个分组';
  }

  Widget _buildControls(List<BookSource> sources, bool compact) {
    final groups = widget.controller.sourceGroups;
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 32, 16, compact ? 16 : 32, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (groups.isNotEmpty)
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: const Key('discover-group-all'),
                      label: const Text('全部分组'),
                      selected: _group == null,
                      showCheckmark: false,
                      selectedColor: AppColors.softBlue,
                      side: BorderSide.none,
                      onSelected: (_) => setState(() => _group = null),
                    ),
                  ),
                  for (final group in groups)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: ValueKey('discover-group-$group'),
                        label: Text(group),
                        selected: _group == group,
                        showCheckmark: false,
                        selectedColor: AppColors.softBlue,
                        side: BorderSide.none,
                        onSelected: (_) => setState(() => _group = group),
                      ),
                    ),
                ],
              ),
            ),
          if (_mode == ExploreMode.content)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        key: const Key('discover-source-select'),
                        isExpanded: true,
                        value: _selection.sourceUrl,
                        hint: const Text('选择书源'),
                        items: [
                          for (final source in sources)
                            DropdownMenuItem(
                              value: source.id,
                              child: Text(
                                source.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) unawaited(_setSource(value));
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBrowse(List<BookSource> sources, bool compact) {
    if (sources.isEmpty) {
      return ListView(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 32,
          8,
          compact ? 16 : 32,
          28,
        ),
        children: [
          EmptyState(
            title: '还没有可浏览的书源',
            description: '在“书源”里导入你有权访问的书库配置，并打开它的“发现”开关，这里就会列出它的发现分类。',
            action: TextButton(
              onPressed: widget.onSources,
              child: const Text('去管理书源'),
            ),
          ),
        ],
      );
    }
    if (_mode == ExploreMode.content) return _buildContent(sources, compact);
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 32, 0, compact ? 16 : 32, 28),
      itemCount: sources.length,
      itemBuilder: (context, index) {
        final source = sources[index];
        return _SourceSection(
          key: ValueKey('discover-source-${source.id}'),
          source: source,
          kinds: _kindsBySource[source.id] ?? const ExploreKindSet.empty(),
          values: _infoBySource[source.id] ?? const {},
          onOpen: (kind) => _openKind(source, kind),
          onButton: (kind) => _onKindButton(source, kind),
          onValueChanged: (kind, value) => _onKindValue(source, kind, value),
        );
      },
    );
  }

  /// 内容模式：一次一条书源，顶部是它的分类标签，下面是当前分类的书籍列表。
  Widget _buildContent(List<BookSource> sources, bool compact) {
    final source = _sourceFor(_selection.sourceUrl) ?? sources.first;
    final kinds = loadableExploreKinds(
      (_kindsBySource[source.id] ?? const ExploreKindSet.empty()).kinds,
    );
    final selectedKindKey = _selection.kindKeyFor(source.id);
    final selected = kinds.firstWhere(
      (kind) => kind.key == selectedKindKey,
      orElse: () => kinds.isEmpty ? const ExploreKind(title: '') : kinds.first,
    );
    final page = _page;
    final showingCurrent =
        page != null &&
        page.source.id == source.id &&
        page.kind.key == selected.key;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kinds.isNotEmpty)
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 32),
              children: [
                for (final kind in kinds)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('discover-kind-${source.id}-${kind.title}'),
                      label: Text(kind.title),
                      selected: kind.key == selected.key,
                      showCheckmark: false,
                      selectedColor: AppColors.softBlue,
                      side: BorderSide.none,
                      onSelected: (_) => unawaited(_setKind(source.id, kind)),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: kinds.isEmpty
              ? ListView(
                  padding: EdgeInsets.all(compact ? 16 : 32),
                  children: const [
                    EmptyState(
                      title: '这条书源没有可浏览的分类',
                      description: '它的发现规则可能由脚本生成，当前版本无法加载。',
                    ),
                  ],
                )
              : showingCurrent
              ? _buildPage(page, compact)
              : _buildKindPlaceholder(source, selected, compact),
        ),
      ],
    );
  }

  Widget _buildKindPlaceholder(
    BookSource source,
    ExploreKind kind,
    bool compact,
  ) => ListView(
    padding: EdgeInsets.fromLTRB(compact ? 16 : 32, 8, compact ? 16 : 32, 28),
    children: [
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const Key('discover-kind-open'),
          onPressed: kind.isLoadable
              ? () => unawaited(_openKind(source, kind, keepMode: true))
              : null,
          child: Text('浏览“${kind.title}”'),
        ),
      ),
    ],
  );

  Widget _buildPage(_ExplorePage page, bool compact) {
    final books = page.books;
    return ListView(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 32, 8, compact ? 16 : 32, 28),
      children: [
        if (page.loading && books.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (page.error != null && books.isEmpty)
          EmptyState(
            title: '这个分类暂时没有加载出来',
            description: page.error!,
            action: TextButton(
              key: const Key('discover-page-retry'),
              onPressed: () => unawaited(_loadPage(page, 1)),
              child: const Text('重试'),
            ),
          ),
        if (books.isNotEmpty && page.error == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '共 ${books.length} 本',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
        for (final book in books.take(_pageBookLimit))
          _ExploreBookTile(
            key: ValueKey('discover-book-${book.id}'),
            book: book,
            controller: widget.controller,
            inShelf: widget.controller.book(book.id) != null,
            onTap: () => widget.onDetails(book),
          ),
        if (page.hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Center(
              child: OutlinedButton(
                key: const Key('discover-page-more'),
                onPressed: page.loading
                    ? null
                    : () => unawaited(_loadPage(page, page.page + 1)),
                child: Text(page.loading ? '加载中…' : '下一页'),
              ),
            ),
          ),
      ],
    );
  }
}

/// 一次打开的分类列表状态；`generation` 用来丢弃迟到的旧请求结果。
class _ExplorePage {
  _ExplorePage({required this.source, required this.kind});

  final BookSource source;
  final ExploreKind kind;
  final int generation = _sequence++;
  static int _sequence = 0;

  Completer<void> abort = Completer<void>();
  List<Book> books = const [];
  bool loading = false;
  bool hasMore = false;
  int page = 1;
  String? error;
}

/// 浏览模式里的一条书源：标题、状态、以及它自己的发现分类。
class _SourceSection extends StatelessWidget {
  const _SourceSection({
    super.key,
    required this.source,
    required this.kinds,
    required this.values,
    required this.onOpen,
    required this.onButton,
    required this.onValueChanged,
  });

  final BookSource source;
  final ExploreKindSet kinds;
  final Map<String, String> values;
  final ValueChanged<ExploreKind> onOpen;
  final ValueChanged<ExploreKind> onButton;
  final void Function(ExploreKind kind, String value) onValueChanged;

  @override
  Widget build(BuildContext context) {
    final rows = kinds.kinds;
    final groups = source.groups;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: QuietPanel(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                if (groups.isNotEmpty)
                  Flexible(
                    child: Text(
                      groups.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
              ],
            ),
            if (source.comment.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                source.comment,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: AppColors.muted,
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (kinds.isUnsupported)
              Text(
                kinds.unsupportedReason ?? '这条书源的发现分类无法加载。',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              )
            else if (rows.isEmpty)
              const Text(
                '这条书源没有声明发现分类。',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              )
            else
              ExploreKindRow(
                source: source.id,
                kinds: rows,
                values: values,
                onOpen: onOpen,
                onButton: onButton,
                onValueChanged: onValueChanged,
              ),
          ],
        ),
      ),
    );
  }
}

/// 发现页的书籍行：封面 + 书名 + 作者分类。
class _ExploreBookTile extends StatelessWidget {
  const _ExploreBookTile({
    super.key,
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
                  width: 66,
                  height: 92,
                ),
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
                          fontSize: 12,
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

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPress,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: _circleFill,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPress,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, size: 20, color: AppColors.ink),
        ),
      ),
    ),
  );
}
