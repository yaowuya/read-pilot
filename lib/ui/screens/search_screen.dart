import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../domain/book_source.dart';
import '../../domain/search_merge.dart';
import '../components/book_cover.dart';
import '../components/common.dart';
import '../components/design.dart';
import '../design_icons.dart';
import '../theme.dart';

/// 设计稿里搜索页用的一组中性灰，主题色板没有收录。
const _scopeInk = Color(0xFF687484);
const _scopeIconInk = Color(0xFF8994A3);
const _exactInk = Color(0xFF7D8692);
const _checkBorder = Color(0xFFBDC5D0);
const _headInk = Color(0xFF657183);
const _headStrongInk = Color(0xFF303946);
const _progressInk = Color(0xFF929AA6);
const _completeInk = Color(0xFFA1A8B2);
const _titleInk = Color(0xFF30333B);
const _originFill = Color(0xFFF0F4FA);
const _originInk = Color(0xFF6F8CAF);
const _authorInk = Color(0xFF7C8796);
const _latestInk = Color(0xFF909AA7);
const _descriptionInk = Color(0xFF7F8997);
const _tagBorder = Color(0xFFE9EDF2);
const _tagInk = Color(0xFFA0A8B2);
const _sectionTitleInk = Color(0xFF414A57);
const _historyInk = Color(0xFF697483);
const _historyMutedInk = Color(0xFFA4ABB6);
const _idleIconFill = Color(0xFFF6F8FB);
const _idleIconInk = Color(0xFFB3C2D6);
const _idleTitleInk = Color(0xFF959FAA);
const _idleInk = Color(0xFFABB3BE);
const _emptyIconInk = Color(0xFFB5C4D8);
const _emptyTitleInk = Color(0xFF5C6879);
const _emptyInk = Color(0xFFA0A9B6);
const _footInk = Color(0xFFAFB7C2);
const _rowBorder = Color(0xFFEEF0F3);
const _historyBorder = Color(0xFFF2F3F6);
const _searchFill = Color(0xFFF4F5F7);

/// 搜索：按设计稿整页呈现条件、结果与历史。
///
/// 检索本身沿用 `controller.searchSources`：并发查询所有启用的书源、边出结果边
/// 合并同名书。本页只负责把结果按稿排版，并在提交时把关键词写入本机历史。
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.controller,
    required this.onDetails,
    this.initialQuery = '',
    this.source,
    this.onManageSources,
  });

  final AppController controller;
  final ValueChanged<Book> onDetails;
  final String initialQuery;

  /// 限定在这一个书源里搜索；为空时搜全部已启用书源。
  final BookSource? source;

  /// 范围面板底部的「管理书源」；不传则不显示这条入口。
  final VoidCallback? onManageSources;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  String _submitted = '';
  List<SourceSearchGroup> _remote = [];
  bool _searching = false;
  bool _paused = false;
  int _generation = 0;
  int _processed = 0;
  int _total = 0;
  Completer<void>? _abort;
  List<String> _history = const [];
  bool _exact = false;
  final Set<String> _scopeGroups = {};
  final Set<String> _scopeSources = {};

  @override
  void initState() {
    super.initState();
    _query.text = widget.initialQuery;
    final anchor = widget.source;
    if (anchor != null) _scopeSources.add(anchor.id);
    unawaited(_loadHistory());
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_search());
      });
    }
  }

  @override
  void dispose() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    _query.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 范围筛选

  List<BookSource> get _searchableSources => [
    for (final source in widget.controller.sources)
      if (source.enabled) source,
  ];

  /// 当前范围内真正参与搜索的书源。空范围表示全部已启用书源。
  List<BookSource> get _scopedSources {
    final all = _searchableSources;
    if (_scopeSources.isNotEmpty) {
      return [
        for (final source in all)
          if (_scopeSources.contains(source.id)) source,
      ];
    }
    if (_scopeGroups.isNotEmpty) {
      return [
        for (final source in all)
          if (source.groups.any(_scopeGroups.contains)) source,
      ];
    }
    return all;
  }

  /// 与设计稿 `scopeLabel` 一致：单个书源显示名字，多个显示计数。
  String get _scopeLabel {
    if (_scopeSources.length == 1) {
      final id = _scopeSources.first;
      for (final source in widget.controller.sources) {
        if (source.id == id) return source.name;
      }
      return '所选书源';
    }
    if (_scopeSources.isNotEmpty) return '${_scopeSources.length} 个书源';
    if (_scopeGroups.length == 1) return _scopeGroups.first;
    if (_scopeGroups.isNotEmpty) return '${_scopeGroups.length} 个分组';
    return '全部书源';
  }

  // ------------------------------------------------------------------ 历史

  Future<void> _loadHistory() async {
    final items = await widget.controller.searchHistory();
    if (!mounted) return;
    setState(() => _history = items);
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

  Future<void> _deleteHistory(String keyword) async {
    // 存储层只有整表读写，删一条等于写回剩下的关键词。
    final kept = [
      for (final item in _history)
        if (item != keyword) item,
    ];
    await widget.controller.clearSearchHistory();
    for (final item in kept.reversed) {
      await widget.controller.rememberSearch(item);
    }
    final items = await widget.controller.searchHistory();
    if (mounted) setState(() => _history = items);
  }

  // ------------------------------------------------------------------ 检索

  Future<void> _search() async {
    final keyword = _query.text.trim();
    if (keyword.isEmpty) return;
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    final generation = ++_generation;
    final abort = Completer<void>();
    setState(() {
      _submitted = keyword;
      _searching = true;
      _paused = false;
      _remote = [];
      _processed = 0;
      _total = _searchableSources.length;
      _abort = abort;
    });
    unawaited(_remember(keyword));
    final groups = await widget.controller.searchSources(
      keyword,
      abortTrigger: abort.future,
      onResult: (group, processed, total) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _remote = [..._remote, group];
          _processed = processed;
          _total = total;
        });
      },
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _searching = false;
      _remote = groups;
      _processed = groups.length;
      _abort = null;
    });
  }

  /// 停止：保留已出的结果，按稿进入 paused 态。
  void _stop() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    _generation++;
    setState(() {
      _searching = false;
      _paused = true;
      _abort = null;
    });
  }

  void _resume() {
    if (_submitted.isEmpty) return;
    _query.text = _submitted;
    unawaited(_search());
  }

  bool get _hasRun => _submitted.isNotEmpty || _paused;

  // ------------------------------------------------------------------ 结果

  bool _matchesExact(String value, String keyword) =>
      value.trim().toLowerCase() == keyword;

  List<MergedBookResult> get _results {
    final merged = mergeSearchResults([
      for (final group in _remote) (source: group.source, books: group.books),
    ], keyword: _submitted);
    final allowed = {for (final source in _scopedSources) source.id};
    final narrowed = [
      for (final result in merged)
        if (result.sources.any((source) => allowed.contains(source.id))) result,
    ];
    if (!_exact) return narrowed;
    final keyword = _submitted.trim().toLowerCase();
    return [
      for (final result in narrowed)
        if (_matchesExact(result.primary.title, keyword) ||
            _matchesExact(result.primary.author, keyword))
          result,
    ];
  }

  /// 没有可搜索书源时，退回到本机书架做同样的匹配。
  List<Book> get _localMatches {
    final keyword = _submitted.trim().toLowerCase();
    if (keyword.isEmpty) return const [];
    return [
      for (final book in widget.controller.books)
        if (_exact
            ? _matchesExact(book.title, keyword) ||
                  _matchesExact(book.author, keyword)
            : book.title.toLowerCase().contains(keyword) ||
                  book.author.toLowerCase().contains(keyword))
          book,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        onBack: () => Navigator.of(context).maybePop(),
        title: '搜索',
        actions: [
          CircleIconButton(
            key: const Key('search-scope'),
            icon: DesignIcons.sliders,
            tooltip: '选择搜索范围',
            onPressed: _showScope,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(23, 8, 23, 0),
            child: Row(
              children: [
                Expanded(
                  child: SearchPill(
                    controller: _query,
                    fieldKey: const Key('search-field'),
                    autofocus: widget.initialQuery.isEmpty,
                    hintText: '搜索书名、作者',
                    trailing: _query.text.isEmpty ? null : _clearButton(),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 14),
                TextButton(
                  key: const Key('search-submit'),
                  onPressed: _searching ? _stop : _search,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(31, 44),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: const Color(0xFF3279DC),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),
          _conditions(),
          Expanded(child: _hasRun ? _resultsView() : _idleView()),
        ],
      ),
    );
  }

  Widget _clearButton() => Padding(
    padding: const EdgeInsets.only(right: 5),
    child: IconButton(
      key: const Key('search-clear'),
      tooltip: '清空搜索',
      onPressed: () {
        _query.clear();
        setState(() {});
      },
      visualDensity: VisualDensity.compact,
      iconSize: 16,
      color: AppColors.muted,
      icon: const Icon(DesignIcons.close),
    ),
  );

  Widget _conditions() => Container(
    height: 58,
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 23),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              key: const Key('search-scope-trigger'),
              onTap: _showScope,
              borderRadius: BorderRadius.circular(AppRadii.button),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      DesignIcons.layers,
                      size: 15,
                      color: _scopeIconInk,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _scopeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: _scopeInk),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      DesignIcons.chevronDown,
                      size: 12,
                      color: _scopeIconInk,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        InkWell(
          key: const Key('search-exact'),
          onTap: () => setState(() => _exact = !_exact),
          borderRadius: BorderRadius.circular(AppRadii.button),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _exact ? AppColors.blue : Colors.transparent,
                    border: Border.all(
                      color: _exact ? AppColors.blue : _checkBorder,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: _exact
                      ? const Icon(DesignIcons.check, size: 11, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 6),
                Text(
                  '精确搜索',
                  style: TextStyle(
                    fontSize: 11,
                    color: _exact ? AppColors.blue : _exactInk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  // -------------------------------------------------------------- 结果视图

  Widget _resultsView() {
    final results = _results;
    final searchingSources = _scopedSources.length;
    final showLocal = searchingSources == 0;
    final local = showLocal ? _localMatches : const <Book>[];
    final count = showLocal ? local.length : results.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(23, 0, 23, 22),
      children: [
        _resultsHead(count, searchingSources),
        if (_searching)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _total == 0
                  ? null
                  : (_processed / _total).clamp(0.0, 1.0).toDouble(),
              minHeight: 2,
              backgroundColor: const Color(0xFFEDF2F8),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF7EAfea)),
            ),
          ),
        if (count == 0)
          _emptyBlock(searchingSources)
        else if (showLocal)
          for (final book in local)
            _LocalRow(
              book: book,
              controller: widget.controller,
              onDetails: () => widget.onDetails(book),
            )
        else
          for (final result in results)
            _ResultRow(
              key: ValueKey('search-result-${result.primary.id}'),
              book: result.primary,
              controller: widget.controller,
              sourceCount: result.sourceCount,
              inShelf: widget.controller.book(result.primary.id) != null,
              onDetails: () => widget.onDetails(result.primary),
            ),
        if (showLocal)
          Padding(
            padding: const EdgeInsets.only(top: 22),
            child: Center(
              child: Text.rich(
                TextSpan(
                  text: '没有启用的书源，以上为本地匹配。',
                  children: [
                    if (widget.onManageSources != null)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: InkWell(
                          key: const Key('search-manage-sources'),
                          onTap: widget.onManageSources,
                          child: const Text(
                            ' 管理书源',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF7C9DCA),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.8,
                  color: Color(0xFF9AA4B1),
                ),
              ),
            ),
          ),
        if (_paused && !_searching)
          Container(
            margin: const EdgeInsets.only(top: 18),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Text(
              '搜索已停止，已找到的结果会保留。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Color(0xFF98A3B1)),
            ),
          ),
        _demoNote(),
      ],
    );
  }

  Widget _resultsHead(int count, int searchingSources) {
    final String status;
    if (searchingSources == 0) {
      status = ' · 书架与本地';
    } else if (_searching) {
      status = ' · 已搜索 $_processed/$_total 个源';
    } else {
      status = ' · 已搜索 ${_total == 0 ? searchingSources : _total} 个源';
    }
    final Widget trailing;
    if (_searching) {
      trailing = TextButton(
        key: const Key('search-stop'),
        onPressed: _stop,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.only(left: 12),
          foregroundColor: const Color(0xFF979EAA),
          textStyle: const TextStyle(fontSize: 11),
        ),
        child: const Text('停止'),
      );
    } else if (_paused) {
      trailing = TextButton(
        key: const Key('search-resume'),
        onPressed: _resume,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.only(left: 12),
          foregroundColor: const Color(0xFF979EAA),
          textStyle: const TextStyle(fontSize: 11),
        ),
        child: const Text('继续'),
      );
    } else {
      trailing = Text(
        searchingSources == 0 ? '仅搜索本地' : '搜索完成',
        style: const TextStyle(fontSize: 10, color: _completeInk),
      );
    }
    return Container(
      key: const Key('search-results-head'),
      constraints: const BoxConstraints(minHeight: 54),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$count',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _headStrongInk,
                    ),
                  ),
                  const TextSpan(text: ' 本书'),
                  TextSpan(
                    text: status,
                    style: const TextStyle(fontSize: 10, color: _progressInk),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 11, color: _headInk),
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _emptyBlock(int searchingSources) {
    final String title;
    final String help;
    if (_searching) {
      title = '正在查找这本书';
      help = '已返回的结果会陆续显示在这里。';
    } else if (searchingSources == 0) {
      title = '当前没有可搜索的书源';
      help = '书架与本地书籍仍然可以查找。';
    } else if (_exact) {
      title = '没有完全匹配的书名或作者';
      help = '试试关闭精确搜索，扩大匹配范围。';
    } else {
      title = '没有找到相关书籍';
      help = '可以换个关键词，或调整书源范围。';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 47, bottom: 27),
      child: Column(
        children: [
          Icon(
            _searching ? DesignIcons.search : DesignIcons.bookOpen,
            size: 34,
            color: _emptyIconInk,
          ),
          const SizedBox(height: 22),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: _emptyTitleInk,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            help,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, height: 1.9, color: _emptyInk),
          ),
          const SizedBox(height: 25),
          if (!_searching) ...[
            if (searchingSources == 0 && widget.onManageSources != null)
              OutlinedButton(
                key: const Key('search-manage-sources-empty'),
                onPressed: widget.onManageSources,
                child: const Text('管理书源'),
              )
            else if (_exact)
              OutlinedButton(
                key: const Key('search-exact-off'),
                onPressed: () => setState(() => _exact = false),
                child: const Text('关闭精确搜索'),
              )
            else
              OutlinedButton(
                key: const Key('search-adjust-scope'),
                onPressed: _showScope,
                child: const Text('调整搜索范围'),
              ),
          ],
        ],
      ),
    );
  }

  Widget _demoNote() => Padding(
    padding: const EdgeInsets.only(top: 29, bottom: 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(DesignIcons.info, size: 12, color: _footInk),
        SizedBox(width: 5),
        Text(
          '搜索进度与来源数来自各书源',
          style: TextStyle(fontSize: 9, height: 1.8, color: _footInk),
        ),
      ],
    ),
  );

  // -------------------------------------------------------------- 未提交态

  Widget _idleView() {
    final sources = _scopedSources;
    return ListView(
      padding: const EdgeInsets.fromLTRB(23, 0, 23, 22),
      children: [
        const SizedBox(height: 23),
        Row(
          children: [
            const Expanded(
              child: Text(
                '搜索历史',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: _sectionTitleInk,
                ),
              ),
            ),
            if (_history.isNotEmpty)
              TextButton(
                key: const Key('search-history-clear'),
                onPressed: _clearHistory,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.only(left: 12),
                  foregroundColor: const Color(0xFF979EAA),
                  textStyle: const TextStyle(fontSize: 11),
                ),
                child: const Text('清空'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Text(
              '暂无搜索记录',
              style: TextStyle(fontSize: 12, color: _historyMutedInk),
            ),
          )
        else
          for (final keyword in _history) _historyRow(keyword),
        const SizedBox(height: 20),
        Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(
                color: _idleIconFill,
                shape: BoxShape.circle,
              ),
              child: const Icon(DesignIcons.search, size: 22, color: _idleIconInk),
            ),
            const SizedBox(height: 18),
            const Text(
              '从一本想读的书开始',
              style: TextStyle(fontSize: 14, color: _idleTitleInk),
            ),
            const SizedBox(height: 12),
            Text(
              sources.isEmpty
                  ? '输入书名或作者，点击搜索。\n也可以查找书架与本地书籍。'
                  : '输入书名或作者，点击搜索。\n在 ${sources.length} 个已启用书源中查找。',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                height: 1.9,
                color: _idleInk,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _historyRow(String keyword) => Container(
    constraints: const BoxConstraints(minHeight: 53),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _historyBorder)),
    ),
    child: Row(
      children: [
        Expanded(
          child: InkWell(
            key: ValueKey('search-history-$keyword'),
            onTap: () {
              _query.text = keyword;
              unawaited(_search());
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  const Icon(DesignIcons.rotateCcw, size: 16, color: Color(0xFFB2BBC7)),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      keyword,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: _historyInk),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          key: ValueKey('search-history-delete-$keyword'),
          tooltip: '删除搜索记录：$keyword',
          onPressed: () => _deleteHistory(keyword),
          iconSize: 15,
          color: const Color(0xFFBAC1CB),
          icon: const Icon(DesignIcons.close),
        ),
      ],
    ),
  );

  // -------------------------------------------------------------- 范围面板

  Future<void> _showScope() async {
    final groups = widget.controller.sourceGroups;
    final sources = _searchableSources;
    final chosenGroups = {..._scopeGroups};
    final chosenSources = {..._scopeSources};
    var tab = chosenSources.isNotEmpty ? 'sources' : 'groups';
    final filter = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final keyword = filter.text.trim().toLowerCase();
          final all = chosenGroups.isEmpty && chosenSources.isEmpty;
          final rows = <Widget>[];
          if (tab == 'sources') {
            for (final source in sources) {
              if (keyword.isNotEmpty &&
                  !'${source.name} ${source.groups.join(' ')}'
                      .toLowerCase()
                      .contains(keyword)) {
                continue;
              }
              rows.add(
                _ScopeOption(
                  key: ValueKey('search-scope-source-${source.id}'),
                  title: source.name,
                  subtitle: source.groups.join(' · '),
                  selected: chosenSources.contains(source.id),
                  onTap: () => setSheetState(() {
                    if (!chosenSources.remove(source.id)) {
                      chosenSources.add(source.id);
                      chosenGroups.clear();
                    }
                  }),
                ),
              );
            }
          } else {
            for (final group in groups) {
              if (keyword.isNotEmpty &&
                  !group.toLowerCase().contains(keyword)) {
                continue;
              }
              final members = sources
                  .where((source) => source.groups.contains(group))
                  .length;
              rows.add(
                _ScopeOption(
                  key: ValueKey('search-scope-group-$group'),
                  title: group,
                  subtitle: '$members 个书源',
                  selected: chosenGroups.contains(group),
                  onTap: () => setSheetState(() {
                    if (!chosenGroups.remove(group)) {
                      chosenGroups.add(group);
                      chosenSources.clear();
                    }
                  }),
                ),
              );
            }
          }
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * .86,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
                    child: Row(
                      children: [
                        IconButton(
                          key: const Key('search-scope-cancel'),
                          tooltip: '取消范围选择',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          color: const Color(0xFF8F99A7),
                          icon: const Icon(DesignIcons.close, size: 20),
                        ),
                        const Expanded(
                          child: Text(
                            '搜索范围',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        TextButton(
                          key: const Key('search-scope-done'),
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                          },
                          style: TextButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            foregroundColor: AppColors.blue,
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 23),
                      child: Column(
                        children: [
                          Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: _searchFill,
                              borderRadius: BorderRadius.circular(
                                AppRadii.pill,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  DesignIcons.search,
                                  size: 17,
                                  color: AppColors.muted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    key: const Key('search-scope-field'),
                                    controller: filter,
                                    onChanged: (_) => setSheetState(() {}),
                                    style: const TextStyle(fontSize: 13),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                      hintText: '筛选分组或书源',
                                      hintStyle: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          _ScopeOption(
                            key: const Key('search-scope-all'),
                            title: '全部书源',
                            subtitle: '${sources.length} 个已启用',
                            selected: all,
                            onTap: () => setSheetState(() {
                              chosenGroups.clear();
                              chosenSources.clear();
                            }),
                          ),
                          Row(
                            children: [
                              for (final entry in const [
                                ('groups', '分组'),
                                ('sources', '书源'),
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(
                                    right: 8,
                                    top: 6,
                                  ),
                                  child: TextButton(
                                    key: ValueKey(
                                      'search-scope-tab-${entry.$1}',
                                    ),
                                    onPressed: () =>
                                        setSheetState(() => tab = entry.$1),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(0, 34),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      backgroundColor: tab == entry.$1
                                          ? AppColors.softBlue
                                          : Colors.transparent,
                                      foregroundColor: tab == entry.$1
                                          ? AppColors.blue
                                          : AppColors.muted,
                                      textStyle: const TextStyle(fontSize: 12),
                                    ),
                                    child: Text(entry.$2),
                                  ),
                                ),
                            ],
                          ),
                          Expanded(
                            child: ListView(
                              padding: EdgeInsets.zero,
                              children: rows.isEmpty
                                  ? const [
                                      Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 22,
                                        ),
                                        child: Text(
                                          '没有符合条件的书源或分组',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _historyMutedInk,
                                          ),
                                        ),
                                      ),
                                    ]
                                  : rows,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 14),
                            child: Column(
                              children: [
                                const Text(
                                  '可多选分组或书源，点击完成后生效。',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _historyMutedInk,
                                  ),
                                ),
                                if (widget.onManageSources != null)
                                  TextButton(
                                    key: const Key('search-scope-manage'),
                                    onPressed: widget.onManageSources,
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF7C9DCA),
                                      textStyle: const TextStyle(fontSize: 12),
                                    ),
                                    child: const Text('管理书源'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    filter.dispose();
    if (!mounted) return;
    setState(() {
      _scopeGroups
        ..clear()
        ..addAll(chosenGroups);
      _scopeSources
        ..clear()
        ..addAll(chosenSources);
    });
    if (_submitted.isNotEmpty && !_searching) unawaited(_search());
  }
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF535E6D),
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFA0A9B5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 18),
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: selected ? AppColors.blue : Colors.transparent,
              border: Border.all(
                color: selected ? AppColors.blue : const Color(0xFFD6DDE6),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: selected
                ? const Icon(DesignIcons.check, size: 13, color: Colors.white)
                : null,
          ),
        ],
      ),
    ),
  );
}

/// 结果行：设计稿 `catalog-book`。
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
    final latest = book.chapters.isEmpty ? '' : book.chapters.last.title;
    final intro = bookIntroText(book.description);
    final tags = <String>[
      if (book.category.trim().isNotEmpty) book.category,
      if (book.chapters.isNotEmpty) '${book.chapters.length} 章',
    ];
    return InkWell(
      onTap: onDetails,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 19),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _rowBorder)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: BookCover(
                      book: book,
                      imageLoader: controller.loadBookCover,
                      width: 72,
                      height: 101,
                    ),
                  ),
                  if (inShelf)
                    Positioned(
                      right: -4,
                      top: -5,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C95CB),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          DesignIcons.check,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                            color: _titleInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      if (sourceCount > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _originFill,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$sourceCount 个源',
                            style: const TextStyle(
                              fontSize: 10,
                              color: _originInk,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  if (book.author.trim().isNotEmpty)
                    Text(
                      book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.7,
                        color: _authorInk,
                      ),
                    ),
                  if (latest.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '最新：$latest',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.7,
                        color: _latestInk,
                      ),
                    ),
                  ],
                  const SizedBox(height: 9),
                  Text(
                    intro.isEmpty ? '暂无简介' : intro,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.8,
                      color: _descriptionInk,
                    ),
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        for (final tag in tags)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: _tagBorder),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                fontSize: 10,
                                color: _tagInk,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 没有可用书源时的本地匹配行。
class _LocalRow extends StatelessWidget {
  const _LocalRow({
    required this.book,
    required this.controller,
    required this.onDetails,
  });

  final Book book;
  final AppController controller;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onDetails,
    child: Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F3F5))),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: BookCover(
              book: book,
              imageLoader: controller.loadBookCover,
              width: 30,
              height: 42,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: Color(0xFF576170),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  book.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: _tagInk),
                ),
              ],
            ),
          ),
          const Icon(DesignIcons.chevronRight, size: 15, color: Color(0xFFB4BDC8)),
        ],
      ),
    ),
  );
}
