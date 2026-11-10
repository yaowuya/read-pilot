import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../domain/book_source.dart';
import '../../domain/explore_kind.dart';
import '../components/book_cover.dart';
import '../components/common.dart';
import '../components/design.dart';
import '../components/explore_kind_row.dart';
import '../design_icons.dart';
import '../theme.dart';
import 'search_screen.dart';

/// 一页发现书籍列表最多展示多少本，和 legado 的榜单首页一致。
const _pageBookLimit = 60;

/// 设计稿 `.discovery-*` 用到的辅助色，只在本页出现。
const _hintInk = Color(0xFFA0A6B0);
const _quietInk = Color(0xFF979EAA);
const _helpInk = Color(0xFFA3AAB5);
const _footInk = Color(0xFFB1B7C0);
const _chipFill = Color(0xFFF5F6F8);
const _chipInk = Color(0xFF5B626D);
const _addInk = Color(0xFF7D92AF);
const _rowTitle = Color(0xFF343942);
const _rowDescription = Color(0xFF959DA9);
const _searchOnlyFill = Color(0xFFF2F4F6);
const _searchOnlyInk = Color(0xFF8A929F);
const _rowChevron = Color(0xFFAFB6C0);

/// 发现页，按设计稿重排：大标题、搜索框、最近搜索、浏览书源。
///
/// 三种层级，逐层下钻：
///  * 根层是设计稿的书源列表：每条书源一行，标出它能不能浏览分类（`分类` /
///    `仅搜索`）。点有分类的书源进它的分类格子，点只有搜索能力的书源直接带着
///    这条书源进搜索页。
///  * 书源层排开这条书源声明的发现分类（[ExploreKindRow]），点分类进入书籍列表。
///  * 书籍列表沿用 legado 的翻页与「已在书架」标记。
///
/// 内容模式（一次只看一条书源）仍由标题区的切换按钮进入，和 legado 一致。
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.controller,
    required this.onDetails,
    required this.onSources,
    this.onOpen,
    this.onBack,
    this.onImport,
  });

  final AppController controller;
  final ValueChanged<Book> onDetails;
  final VoidCallback onSources;

  /// Opens a search hit straight into the reader; falling back to book details
  /// would add a step the discover list never needed.
  final ValueChanged<Book>? onOpen;
  final VoidCallback? onBack;

  /// 空态里的「导入本地书籍」；没有导入能力时不显示这条次链接。
  final VoidCallback? onImport;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

enum ExploreMode { browse, content }

class _DiscoverScreenState extends State<DiscoverScreen> {
  ExploreMainSelection _selection = const ExploreMainSelection();
  ExploreMode _mode = ExploreMode.browse;
  String? _group;

  /// 已进入的书源（书源层），null 表示停留在根列表。
  String? _detailSourceId;

  /// 每条书源的发现分类；脚本生成的分类会有 [ExploreKindSet.unsupportedReason]。
  final _kindsBySource = <String, ExploreKindSet>{};
  final _infoBySource = <String, Map<String, String>>{};

  /// 根层的搜索框，提交后把关键词带进搜索页。
  final _searchQuery = TextEditingController();

  /// 最近搜索，来自本机历史；为空时整块不渲染（设计稿发现页首屏更干净）。
  List<String> _history = const [];

  /// 当前打开的分类列表（书源层点分类、内容模式下也用它）。
  _ExplorePage? _page;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSelection());
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    if (!(_page?.abort.isCompleted ?? true)) _page!.abort.complete();
    _searchQuery.dispose();
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

  Future<void> _loadHistory() async {
    final items = await widget.controller.searchHistory();
    if (!mounted) return;
    setState(() => _history = items);
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

  /// 已进入的书源；分组筛选把它挡住时仍然照常显示，避免点开就消失。
  BookSource? _detailSource() {
    final id = _detailSourceId;
    if (id == null) return null;
    return _sourceFor(id);
  }

  bool _browseable(BookSource source) {
    final kinds = _kindsBySource[source.id] ?? const ExploreKindSet.empty();
    if (kinds.isUnsupported) return false;
    return loadableExploreKinds(kinds.kinds).isNotEmpty;
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

  /// 设计稿：搜索框提交后进搜索页，不再在发现页里内联出结果。
  Future<void> _openSearch({String? initialQuery, BookSource? only}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          controller: widget.controller,
          onDetails: widget.onDetails,
          initialQuery: initialQuery ?? _searchQuery.text.trim(),
          source: only,
          onManageSources: widget.onSources,
        ),
      ),
    );
    if (!mounted) return;
    // 搜索页会把关键词写进历史，回来时根层的「最近搜索」要跟着更新。
    unawaited(_loadHistory());
  }

  Future<void> _clearHistory() async {
    await widget.controller.clearSearchHistory();
    if (!mounted) return;
    setState(() => _history = const []);
  }

  void _openSource(BookSource source) {
    if (_browseable(source)) {
      setState(() => _detailSourceId = source.id);
      return;
    }
    // 只有搜索能力的书源没有分类可逛，直接带着这条书源去搜。
    unawaited(
      _openSearch(initialQuery: _searchQuery.text.trim(), only: source),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 650;
      final page = _page;
      if (page != null) return _buildPageView(page, compact);
      final detail = _detailSource();
      if (detail != null) return _buildSourceLayer(detail, compact);
      final sources = widget.controller.exploreSourcesInGroup(_group);
      return _mode == ExploreMode.content
          ? _buildContentMode(sources, compact)
          : _buildBrowseRoot(sources, compact);
    },
  );

  // ---------------------------------------------------------------- 根层

  Widget _buildBrowseRoot(List<BookSource> sources, bool compact) {
    final all = widget.controller.exploreSources;
    final groups = widget.controller.sourceGroups;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        compact ? AppSpacing.page : 32,
        compact ? 12 : 24,
        compact ? 19 : 32,
        compact ? 22 : 28,
      ),
      children: [
        _buildTitleRow(),
        const SizedBox(height: 20),
        _buildSearchRow(),
        const SizedBox(height: 10),
        Text(
          all.isEmpty ? '可以先搜索书架与本地书籍' : '搜索书架与已启用的书源',
          style: const TextStyle(fontSize: 10, height: 1.7, color: _hintInk),
        ),
        if (_history.isNotEmpty) ...[
          SectionLabel(
            '最近搜索',
            trailing: TextButton(
              key: const Key('discover-history-clear'),
              onPressed: () => unawaited(_clearHistory()),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.only(left: 12),
                foregroundColor: _quietInk,
                textStyle: const TextStyle(fontSize: 11),
              ),
              child: const Text('清空'),
            ),
          ),
          _buildHistoryChips(),
          const SizedBox(height: 30),
        ] else
          const SizedBox(height: 30),
        _buildSourcesHead(sources),
        if (groups.isNotEmpty) ...[
          const SizedBox(height: 2),
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
                    backgroundColor: Colors.transparent,
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
                      backgroundColor: Colors.transparent,
                      selectedColor: AppColors.softBlue,
                      side: BorderSide.none,
                      onSelected: (_) => setState(() => _group = group),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (sources.isEmpty)
          all.isEmpty
              ? _buildNoSourceEmpty()
              : const EmptyState(
                  title: '这个分组还没有发现书源',
                  description: '换一个分组，或者把书源分到这个分组里。',
                )
        else ...[
          Column(
            children: [
              for (final source in sources)
                _DiscoverSourceRow(
                  key: ValueKey('discover-source-${source.id}'),
                  source: source,
                  description: _rowDescription(source),
                  browseable: _browseable(source),
                  onTap: () => _openSource(source),
                ),
            ],
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const Key('discover-add-source'),
            onPressed: widget.onSources,
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              foregroundColor: _addInk,
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(DesignIcons.plus, size: 16),
                SizedBox(width: 7),
                Text('添加书源'),
              ],
            ),
          ),
          const Text(
            '分类由各书源提供。只有搜索功能的书源，\n也可以通过顶部搜索找到书。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, height: 1.9, color: _helpInk),
          ),
        ],
        const SizedBox(height: 29),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(DesignIcons.info, size: 12, color: _footInk),
            SizedBox(width: 5),
            Text(
              '书源与分类都由你自己维护',
              style: TextStyle(fontSize: 9, height: 1.8, color: _footInk),
            ),
          ],
        ),
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _buildTitleRow() => Row(
    children: [
      if (widget.onBack != null)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: CircleIconButton(
            key: const Key('discover-back'),
            icon: DesignIcons.chevronLeft,
            tooltip: '返回书架',
            onPressed: widget.onBack!,
          ),
        ),
      Expanded(
        child: LargeTitle(
          title: '发现',
          trailing: [
            CircleIconButton(
              key: const Key('discover-sources'),
              icon: DesignIcons.sliders,
              tooltip: '管理发现来源',
              onPressed: widget.onSources,
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildSearchRow() => Container(
    height: 52,
    decoration: BoxDecoration(
      color: const Color(0xFFF5F6F8),
      borderRadius: BorderRadius.circular(12),
    ),
    padding: const EdgeInsets.only(left: 14),
    child: Row(
      children: [
        const Icon(DesignIcons.search, size: 19, color: Color(0xFF949AA5)),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            key: const Key('discover-search-field'),
            controller: _searchQuery,
            onSubmitted: (_) => unawaited(_openSearch()),
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(fontSize: 14, color: Color(0xFF2B2E35)),
            cursorColor: AppColors.blue,
            decoration: const InputDecoration(
              isDense: true,
              filled: false,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: '搜索书名、作者',
              hintStyle: TextStyle(fontSize: 14, color: Color(0xFF9DA3AD)),
            ),
          ),
        ),
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Color(0xFFE5E8ED))),
          ),
          child: TextButton(
            key: const Key('discover-search-submit'),
            onPressed: () => unawaited(_openSearch()),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.blue,
              minimumSize: const Size(37, 40),
              padding: const EdgeInsets.only(left: 10, right: 14),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('搜索'),
          ),
        ),
      ],
    ),
  );

  Widget _buildHistoryChips() => Wrap(
    spacing: 9,
    runSpacing: 9,
    children: [
      for (final query in _history)
        InkWell(
          key: ValueKey('discover-history-$query'),
          onTap: () => unawaited(_openSearch(initialQuery: query)),
          borderRadius: BorderRadius.circular(7),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: _chipFill,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              query,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: _chipInk),
            ),
          ),
        ),
    ],
  );

  Widget _buildSourcesHead(List<BookSource> sources) => Row(
    children: [
      const Expanded(
        child: Text(
          '浏览书源',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ),
      if (sources.isNotEmpty)
        Text(
          '${sources.length} 个已启用',
          style: const TextStyle(fontSize: 10, color: _quietInk),
        ),
      const SizedBox(width: 6),
      CircleIconButton(
        key: const Key('discover-mode'),
        icon: DesignIcons.libraryBig,
        tooltip: '切换到分类浏览',
        size: 32,
        onPressed: () => unawaited(_setMode(ExploreMode.content)),
      ),
    ],
  );

  String _rowDescription(BookSource source) {
    final kinds = _kindsBySource[source.id] ?? const ExploreKindSet.empty();
    if (!_browseable(source)) {
      return kinds.unsupportedReason ?? '支持按书名、作者搜索';
    }
    if (source.groups.isNotEmpty) return source.groups.join(' · ');
    final loadable = loadableExploreKinds(kinds.kinds);
    return loadable.map((kind) => kind.title).join(' · ');
  }

  Widget _buildNoSourceEmpty() => EmptyBlock(
    icon: DesignIcons.libraryBig,
    title: '添加书源，发现更多书',
    description: '书源决定能找到哪些书。\n添加后，就可以按书名和作者搜索。',
    primaryLabel: '添加书源',
    onPrimary: widget.onSources,
    secondaryLabel: widget.onImport == null ? null : '导入本地书籍',
    onSecondary: widget.onImport,
  );

  // ---------------------------------------------------------------- 书源层

  Widget _buildSourceLayer(BookSource source, bool compact) {
    final kinds = _kindsBySource[source.id] ?? const ExploreKindSet.empty();
    final values = _infoBySource[source.id] ?? const {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? AppSpacing.page : 32,
            compact ? 10 : 24,
            compact ? AppSpacing.page : 32,
            0,
          ),
          child: Row(
            children: [
              CircleIconButton(
                key: const Key('discover-detail-back'),
                icon: DesignIcons.chevronLeft,
                tooltip: '返回发现',
                onPressed: () => setState(() => _detailSourceId = null),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.3,
                    color: AppColors.ink,
                  ),
                ),
              ),
              CircleIconButton(
                key: const Key('discover-detail-search'),
                icon: DesignIcons.search,
                tooltip: '搜索此书源',
                onPressed: () => unawaited(
                  _openSearch(
                    initialQuery: _searchQuery.text.trim(),
                    only: source,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              compact ? AppSpacing.page : 32,
              18,
              compact ? AppSpacing.page : 32,
              28,
            ),
            children: [
              if (source.groups.isNotEmpty) ...[
                Text(
                  source.groups.join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
              ],
              if (source.comment.isNotEmpty) ...[
                Text(
                  source.comment,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (kinds.isUnsupported)
                Text(
                  kinds.unsupportedReason ?? '这条书源的发现分类无法加载。',
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                )
              else if (kinds.kinds.isEmpty)
                const Text(
                  '这条书源没有声明发现分类。',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                )
              else
                ExploreKindRow(
                  source: source.id,
                  kinds: kinds.kinds,
                  values: values,
                  onOpen: (kind) => unawaited(_openKind(source, kind)),
                  onButton: (kind) => unawaited(_onKindButton(source, kind)),
                  onValueChanged: (kind, value) =>
                      unawaited(_onKindValue(source, kind, value)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------- 内容模式（单源）

  Widget _buildContentMode(List<BookSource> sources, bool compact) {
    if (sources.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? AppSpacing.page : 32,
              compact ? 10 : 24,
              compact ? AppSpacing.page : 32,
              0,
            ),
            child: _buildTitleRow(),
          ),
          const Expanded(child: _NoSourceList()),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? AppSpacing.page : 32,
            compact ? 10 : 24,
            compact ? AppSpacing.page : 32,
            0,
          ),
          child: _buildTitleRow(),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? AppSpacing.page : 32,
            14,
            compact ? AppSpacing.page : 32,
            8,
          ),
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
              const SizedBox(width: 8),
              CircleIconButton(
                key: const Key('discover-mode'),
                icon: DesignIcons.list,
                tooltip: '切换到书源列表',
                size: 32,
                onPressed: () => unawaited(_setMode(ExploreMode.browse)),
              ),
            ],
          ),
        ),
        Expanded(child: _buildContent(sources, compact)),
      ],
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
              padding: EdgeInsets.symmetric(
                horizontal: compact ? AppSpacing.page : 32,
              ),
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
                  padding: EdgeInsets.all(compact ? AppSpacing.page : 32),
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
    padding: EdgeInsets.fromLTRB(
      compact ? AppSpacing.page : 32,
      8,
      compact ? AppSpacing.page : 32,
      28,
    ),
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

  // ------------------------------------------------------------- 书籍列表

  Widget _buildPageView(_ExplorePage page, bool compact) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? AppSpacing.page : 32,
          compact ? 10 : 24,
          compact ? AppSpacing.page : 32,
          0,
        ),
        child: Row(
          children: [
            CircleIconButton(
              key: const Key('discover-page-back'),
              icon: DesignIcons.chevronLeft,
              tooltip: '返回发现',
              onPressed: () => unawaited(_closePage()),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    page.source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.3,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    page.kind.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      Expanded(child: _buildPage(page, compact)),
    ],
  );

  Widget _buildPage(_ExplorePage page, bool compact) {
    final books = page.books;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        compact ? AppSpacing.page : 32,
        8,
        compact ? AppSpacing.page : 32,
        28,
      ),
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

/// 内容模式下一条书源都没有时的说明。
class _NoSourceList extends StatelessWidget {
  const _NoSourceList();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: double.infinity,
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        '还没有启用的发现书源',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: AppColors.muted),
      ),
    ),
  );
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

/// 根层的一条书源：图标、名称、一句说明、能力标签。
class _DiscoverSourceRow extends StatelessWidget {
  const _DiscoverSourceRow({
    super.key,
    required this.source,
    required this.description,
    required this.browseable,
    required this.onTap,
  });

  final BookSource source;
  final String description;
  final bool browseable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: browseable ? AppColors.softBlue : _searchOnlyFill,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                browseable ? DesignIcons.libraryBig : DesignIcons.search,
                size: 20,
                color: browseable ? AppColors.blue : _searchOnlyInk,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _rowTitle,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: _rowDescription,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            PillTag(
              browseable ? '分类' : '仅搜索',
              tone: browseable ? PillTone.blue : PillTone.neutral,
            ),
            const SizedBox(width: 6),
            Icon(
              browseable ? DesignIcons.chevronRight : DesignIcons.search,
              size: 15,
              color: _rowChevron,
            ),
          ],
        ),
      ),
    ),
  );
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
    final intro = bookIntroText(book.description);
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
                    if (intro.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        intro,
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
