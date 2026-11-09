import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../domain/change_source_settings.dart';
import '../../domain/source_switch_candidate.dart';
import '../design_icons.dart';
import '../theme.dart';
import 'book_cover.dart';
import 'common.dart';

/// Presents bounded source-search states and delegates switching to the controller.
class SourceSwitchSheet extends StatefulWidget {
  const SourceSwitchSheet({
    super.key,
    required this.controller,
    required this.book,
  });

  final AppController controller;
  final Book book;

  @override
  State<SourceSwitchSheet> createState() => _SourceSwitchSheetState();
}

class _SourceSwitchSheetState extends State<SourceSwitchSheet> {
  static const _paper = Color(0xFFF1EDE1);
  static const _surface = Color(0xFFFDF9ED);

  /// 打开时占屏比例：上方留出正文，用户能一边看当前页一边挑书源。
  static const _initialSize = .66;

  /// 向上拖到顶时占屏比例。
  static const _maxSize = .9;

  /// 向下拖到底时占屏比例，再往下就是关闭。
  static const _minSize = .4;

  /// 头部图标按钮收紧到 36 见方：一行里要塞下计数、选项、排序、刷新、关闭，
  /// 默认 48 的点击区会把中间那行状态文字挤没。
  static final ButtonStyle _headerButtonStyle = IconButton.styleFrom(
    minimumSize: const Size(36, 36),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );

  final _sheetController = DraggableScrollableController();
  final _filter = TextEditingController();
  SourceCandidateSearchResult? _result;
  Completer<void>? _abort;
  String? _error;
  String? _switchingId;
  bool _loading = true;
  bool _manualReload = false;
  bool _sortBySource = false;
  late ChangeSourceSettings _settings;
  int _processed = 0;
  int _total = 0;
  int _pendingMetadata = 0;

  @override
  void initState() {
    super.initState();
    _settings = widget.controller.changeSourceSettings;
    unawaited(_restoreOrLoad());
  }

  @override
  void dispose() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    _sheetController.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _restoreOrLoad() async {
    try {
      final cached = await widget.controller.sourceCandidateCacheFor(
        widget.book,
      );
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _result = cached;
          _loading = false;
          _processed = 0;
          _total = 0;
          _pendingMetadata = 0;
        });
        return;
      }
    } catch (_) {
      // A corrupted or unavailable cache must not prevent a live source search.
    }
    if (mounted) await _reload();
  }

  /// Start a fresh search. Manual refreshes intentionally clear the displayed
  /// snapshot first: every row that returns afterwards belongs to this run.
  Future<void> _reload({bool manual = false}) async {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    final abort = Completer<void>();
    setState(() {
      _abort = abort;
      _loading = true;
      _manualReload = manual;
      _result = null;
      _error = null;
      _processed = 0;
      _total = 0;
      _pendingMetadata = 0;
    });
    try {
      final result = await widget.controller.reloadSourceCandidatesFor(
        widget.book,
        abortTrigger: abort.future,
        // 上千个书源要搜几分钟：每完成一个就把已找到的候选画出来。
        // 手动刷新已清空旧卡片，下面出现的都是本轮新结果。
        onUpdate: (partial, processed, total) {
          if (!mounted || _abort != abort) return;
          setState(() {
            _result = partial;
            _processed = processed;
            _total = total;
            _pendingMetadata = partial.pendingMetadata;
          });
        },
      );
      if (!mounted || _abort != abort) return;
      setState(() {
        _result = result;
        _loading = false;
        _manualReload = false;
        _pendingMetadata = 0;
        _abort = null;
      });
    } catch (error) {
      if (!mounted || _abort != abort) return;
      setState(() {
        _error = errorMessage(error);
        _loading = false;
        _manualReload = false;
        _pendingMetadata = 0;
        _abort = null;
      });
    }
  }

  Future<void> _switch(Book candidate) async {
    if (_switchingId != null) return;
    setState(() {
      _switchingId = candidate.id;
      _error = null;
    });
    try {
      final switched = await widget.controller.switchBookSource(
        widget.book.id,
        candidate,
      );
      if (mounted) Navigator.pop(context, switched);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(error);
        _switchingId = null;
      });
    }
  }

  /// 当前筛选胶囊选中的取景范围。
  _SourceScope _scope = _SourceScope.all;

  /// 当前书所在书源的分组（已剔除健康校验标签），用于「同分组」胶囊。
  Set<String> get _currentGroups {
    final sourceId = widget.book.sourceId;
    if (sourceId == null) return const <String>{};
    for (final source in widget.controller.sources) {
      if (source.id == sourceId) return source.groups.toSet();
    }
    return const <String>{};
  }

  /// 与当前书源同组的书源 id；为空表示这份书架里算不出分组。
  Set<String> get _sameGroupSourceIds {
    final groups = _currentGroups;
    if (groups.isEmpty) return const <String>{};
    return {
      for (final source in widget.controller.sources)
        if (source.groups.any(groups.contains)) source.id,
    };
  }

  /// 最近一次健康校验有响应的书源 id，作为「仅在线」的依据。
  Set<String> get _onlineSourceIds => {
    for (final source in widget.controller.sources)
      if (source.respondTime > 0) source.id,
  };

  /// 胶囊取景对应的书源白名单；`null` 表示不限制。
  Set<String>? get _scopeSourceIds {
    switch (_scope) {
      case _SourceScope.all:
        return null;
      case _SourceScope.sameGroup:
        final ids = _sameGroupSourceIds;
        return ids.isEmpty ? null : ids;
      case _SourceScope.online:
        final ids = _onlineSourceIds;
        return ids.isEmpty ? null : ids;
    }
  }

  String get _scopeLabel {
    switch (_scope) {
      case _SourceScope.all:
        return '全部书源';
      case _SourceScope.sameGroup:
        return '同分组';
      case _SourceScope.online:
        return '仅在线';
    }
  }

  List<Book> get _visibleCandidates {
    final query = _filter.text.trim().toLowerCase();
    final result = _result;
    final scopeIds = _scopeSourceIds;
    // A row is listed as soon as a source returned this title: the mapped
    // chapter and word count are extra detail that streams in afterwards, so
    // they must never gate the list itself.
    final ranked = (result?.candidates ?? const <Book>[]).indexed.where((
      entry,
    ) {
      final book = entry.$2;
      final matchesQuery =
          book.sourceLabel.toLowerCase().contains(query) ||
          book.author.toLowerCase().contains(query);
      if (!matchesQuery) return false;
      if (scopeIds == null) return true;
      final sourceId = book.sourceId;
      return sourceId != null && scopeIds.contains(sourceId);
    }).toList();
    if (_sortBySource) {
      ranked.sort((left, right) {
        final name = left.$2.sourceLabel.toLowerCase().compareTo(
          right.$2.sourceLabel.toLowerCase(),
        );
        return name != 0 ? name : left.$1.compareTo(right.$1);
      });
    }
    return ranked.map((entry) => entry.$2).toList();
  }

  String _statusText(
    SourceCandidateSearchResult? result,
    List<Book> candidates,
    int sourceCount,
    bool filtering,
  ) {
    if (_loading) {
      final metadataPending =
          _pendingMetadata > 0 && _total > 0 && _processed >= _total;
      if (metadataPending) {
        return _manualReload
            ? '正在加载本次刷新候选的章节与字数…（剩余 $_pendingMetadata）'
            : '正在加载候选章节与字数…（剩余 $_pendingMetadata）';
      }
      if (_manualReload) {
        return _total > 0 ? '正在重新加载书源…（$_processed/$_total）' : '正在重新加载书源…';
      }
      return _total > 0 ? '正在查找其他同名书源…（$_processed/$_total）' : '正在查找其他同名书源…';
    }
    if (result == null) return '候选搜索未完成';
    return filtering
        ? '匹配 ${candidates.length} / ${result.candidates.length} · $sourceCount 个书源'
        : '候选 ${candidates.length} · $sourceCount 个书源';
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final candidates = _visibleCandidates;
    final sourceCount = candidates
        .map((book) => book.sourceId ?? book.sourceLabel)
        .toSet()
        .length;
    final filtering = _filter.text.trim().isNotEmpty;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    // 换源面板是可拖拽的半屏：默认 2/3 屏，往上滑铺开到 90% 方便一次看更多候选，
    // 往下滑逐渐收矮，一直滑到底就关掉。键盘弹出时在面板外让出高度，
    // 这样比例始终按可用高度算，不会把内容挤没。
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: _initialSize,
        minChildSize: _minSize,
        maxChildSize: _maxSize,
        expand: false,
        builder: (context, scrollController) => ColoredBox(
          color: _paper,
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 键盘弹出或用户把面板拖到底时，可用高度只剩一两百像素：
                // 这时只留标题行和筛选框，其余说明块收起，否则 Column 会溢出。
                //
                // 阈值必须明显低于「默认三分之二屏」的实际高度：1080x1920
                // 的机器逻辑高度只有 640，扣掉系统栏再乘 .66 约剩 390，
                // 按 420 判就会把正常打开的换源面板也当成键盘态，
                // 书名、当前来源、筛选胶囊与页脚声明全被裁掉。
                final compact = constraints.maxHeight < 320;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(
                      context,
                      result,
                      candidates,
                      sourceCount,
                      filtering,
                      compact: compact,
                    ),
                    if (_error != null) _errorPanel(),
                    Expanded(
                      child: _results(
                        scrollController,
                        result,
                        candidates,
                        filtering,
                        compact: compact,
                      ),
                    ),
                    if (!compact) _footNote(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 标题行 + 书上下文 + 当前来源 + 筛选框 + 筛选胶囊 + 候选计数 + 进度。
  ///
  /// 整块头部都接受拖拽：用户上手第一反应是抓最上面那条，而不是去够下面的列表。
  Widget _header(
    BuildContext context,
    SourceCandidateSearchResult? result,
    List<Book> candidates,
    int sourceCount,
    bool filtering, {
    required bool compact,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _resizeSheet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 候选数、选项与排序都并进标题这一行：换源要看的就是候选列表，
          // 说明块和单独的状态行只会把候选挤出屏幕。
          Padding(
            key: const Key('source-switch-status'),
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
            child: Row(
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    '换源',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _statusText(result, candidates, sourceCount, filtering),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('source-switch-options'),
                  tooltip: _settings.checkAuthor ? '已限定作者' : '搜索选项',
                  style: _headerButtonStyle,
                  onPressed: _switchingId == null ? _openOptions : null,
                  icon: Icon(
                    _settings.checkAuthor || _settings.sortByWordCount
                        ? DesignIcons.sliders
                        : DesignIcons.sliders,
                    size: 20,
                    color: _settings.checkAuthor || _settings.sortByWordCount
                        ? AppColors.ink
                        : AppColors.muted,
                  ),
                ),
                PopupMenuButton<bool>(
                  key: const Key('source-switch-sort'),
                  tooltip: '排序',
                  enabled: !_loading && _switchingId == null,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 10,
                  ),
                  onSelected: (value) => setState(() => _sortBySource = value),
                  itemBuilder: (_) => [
                    CheckedPopupMenuItem(
                      value: false,
                      checked: !_sortBySource,
                      child: const Text('相关度'),
                    ),
                    CheckedPopupMenuItem(
                      value: true,
                      checked: _sortBySource,
                      child: const Text('书源名称'),
                    ),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(DesignIcons.arrowUpDown, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        _sortBySource ? '书源名称' : '相关度',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '刷新候选',
                  style: _headerButtonStyle,
                  onPressed: !_loading && _switchingId == null
                      ? () => _reload(manual: true)
                      : null,
                  icon: const Icon(DesignIcons.refresh, size: 20),
                ),
                IconButton(
                  tooltip: '关闭',
                  style: _headerButtonStyle,
                  onPressed: _switchingId == null
                      ? () => Navigator.pop(context)
                      : null,
                  icon: const Icon(DesignIcons.close, size: 20),
                ),
              ],
            ),
          ),
          if (!compact) ...[_bookContext(), _currentSource()],
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              key: const Key('source-switch-filter'),
              controller: _filter,
              enabled: _switchingId == null,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '筛选书源或作者',
                // 主题里的 contentPadding 是给整页表单用的，
                // 这里压扁它，多留几行候选。
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                prefixIcon: const Icon(DesignIcons.search, size: 20),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 0,
                ),
                fillColor: _surface,
                isDense: true,
                suffixIcon: _filter.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除筛选',
                        onPressed: _clearFilter,
                        icon: const Icon(DesignIcons.close, size: 18),
                      ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 0,
                ),
              ),
            ),
          ),
          if (!compact) ...[
            _filterPills(),
            _resultsHead(candidates),
            _progressLine(result, candidates),
          ],
        ],
      ),
    );
  }

  /// 书上下文块：换源时先确认「换的是哪本书」，再挑源。
  Widget _bookContext() {
    final book = widget.book;
    final index = book.position.chapterIndex;
    final chapters = book.chapters;
    final title = index >= 0 && index < chapters.length
        ? chapters[index].title
        : null;
    final readTo = title == null
        ? '读到：第 ${index + 1} 章'
        : '读到：第 ${index + 1} 章 · $title';
    return Padding(
      key: const Key('source-switch-book'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Row(
        children: [
          BookCover(
            book: book,
            imageLoader: widget.controller.loadBookCover,
            width: 28,
            height: 40,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF444C59),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '作者：${book.author}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF929BA8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  readTo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFA1A9B5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 当前来源行：让用户随时看到自己现在读的是哪个源。
  Widget _currentSource() {
    return Padding(
      key: const Key('source-switch-current'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Row(
        children: [
          const Text(
            '当前来源',
            style: TextStyle(fontSize: 10, color: Color(0xFFA2AAB5)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              widget.book.sourceLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Color(0xFF7F8B9D)),
            ),
          ),
        ],
      ),
    );
  }

  /// 筛选胶囊行。「同分组」「仅在线」只在真的能算出来时才可点，
  /// 数据不足时置灰，绝不假装筛掉了东西。
  Widget _filterPills() {
    return Padding(
      key: const Key('source-switch-filters'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Wrap(
        spacing: 9,
        runSpacing: 6,
        children: [
          _scopePill(
            key: const Key('source-filter-all'),
            label: '全部书源',
            scope: _SourceScope.all,
            enabled: true,
          ),
          _scopePill(
            key: const Key('source-filter-group'),
            label: '同分组',
            scope: _SourceScope.sameGroup,
            enabled: _sameGroupSourceIds.isNotEmpty,
          ),
          _scopePill(
            key: const Key('source-filter-online'),
            label: '仅在线',
            scope: _SourceScope.online,
            enabled: _onlineSourceIds.isNotEmpty,
          ),
        ],
      ),
    );
  }

  Widget _scopePill({
    required Key key,
    required String label,
    required _SourceScope scope,
    required bool enabled,
  }) {
    final active = _scope == scope;
    return Material(
      key: key,
      color: active ? AppColors.softBlue : const Color(0xFFF5F6F8),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: enabled ? () => setState(() => _scope = scope) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: !enabled
                  ? const Color(0xFFB7BEC8)
                  : active
                  ? AppColors.blue
                  : const Color(0xFF666E7B),
            ),
          ),
        ),
      ),
    );
  }

  /// 候选计数行：左边是当前取景，右边是「N 个候选来源」。
  Widget _resultsHead(List<Book> candidates) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '范围：$_scopeLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF687484)),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${candidates.length} 个候选来源',
            key: const Key('source-switch-count'),
            maxLines: 1,
            style: const TextStyle(fontSize: 10, color: Color(0xFFA0A9B6)),
          ),
        ],
      ),
    );
  }

  /// 进度行：搜索中报进度，结束后说明当前按什么匹配。
  Widget _progressLine(
    SourceCandidateSearchResult? result,
    List<Book> candidates,
  ) {
    final total = _total > 0 ? _total : (result?.candidates.length ?? 0);
    final label = _loading
        ? (_manualReload ? '正在重新加载书源' : '正在查找同名书籍')
        : _error != null
        ? '搜索已中止'
        : '按书名与作者匹配';
    final fraction = _loading
        ? (total > 0 ? (_processed / total).clamp(0.0, 1.0) : 0.0)
        : 1.0;
    return Padding(
      key: const Key('source-switch-progress'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: Color(0xFFA9B2BF)),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _loading && total > 0
                    ? '$_processed / $total'
                    : '${candidates.length} 个候选',
                maxLines: 1,
                style: const TextStyle(fontSize: 9, color: Color(0xFFA9B2BF)),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 2,
              backgroundColor: const Color(0xFFEDF2F8),
              color: const Color(0xFF7EAFEA),
            ),
          ),
        ],
      ),
    );
  }

  /// 页脚声明：换源不动阅读进度，这句话比任何提示条都让人放心。
  Widget _footNote() {
    return Padding(
      key: const Key('source-switch-note'),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                DesignIcons.bookmarkCheck,
                size: 13,
                color: Color(0xFF95A3B5),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  '切换后自动保留阅读进度、书签与笔记',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF95A3B5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '书源与章节信息来自本次搜索结果',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9, color: Color(0xFFBAC2CC)),
          ),
        ],
      ),
    );
  }

  Widget _errorPanel() {
    return Padding(
      key: const Key('source-switch-error'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: QuietPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFB54444)),
              ),
            ),
            TextButton.icon(
              onPressed: _switchingId == null
                  ? () => _reload(manual: true)
                  : null,
              icon: const Icon(DesignIcons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _results(
    ScrollController scrollController,
    SourceCandidateSearchResult? result,
    List<Book> candidates,
    bool filtering, {
    required bool compact,
  }) {
    // 已经有候选在列就不压转圈：下面的列表会随着书源返回继续增长，
    // 上方的进度文字负责表达还在搜索。
    if (_loading && candidates.isEmpty) {
      return const Center(
        key: Key('source-switch-loading'),
        child: CircularProgressIndicator(),
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(16, compact ? 0 : 8, 16, 16),
      itemCount: candidates.length + 1,
      itemBuilder: (context, index) => index == 0
          ? _listHeader(result, candidates, filtering)
          : Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _candidateRow(candidates[index - 1]),
            ),
    );
  }

  /// 列表头：部分书源失败时的说明，以及空态。
  Widget _listHeader(
    SourceCandidateSearchResult? result,
    List<Book> candidates,
    bool filtering,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (result != null && result.failedSources > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${result.failedSources} 个书源暂时不可用，搜索结果可能不完整。',
              key: const Key('source-switch-partial-error'),
              style: const TextStyle(color: Color(0xFF765B25)),
            ),
          ),
        if (result != null && candidates.isEmpty)
          Padding(
            key: Key(
              filtering ? 'source-switch-filter-empty' : 'source-switch-empty',
            ),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                const Icon(
                  DesignIcons.searchX,
                  size: 28,
                  color: Color(0xFFB4BFCD),
                ),
                const SizedBox(height: 10),
                Text(
                  filtering
                      ? '没有匹配的书源或作者'
                      : result.failedSources > 0
                      ? '暂未找到候选'
                      : '没有找到其他同名书源',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8998AC),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  filtering
                      ? '换个关键词，或清除筛选查看全部候选。'
                      : result.failedSources > 0
                      ? '部分书源未能完成搜索，可以点刷新重试。'
                      : '可以点刷新重新扫描全部书源。',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.9,
                    color: Color(0xFFADB7C4),
                  ),
                ),
                if (filtering)
                  TextButton(
                    onPressed: _clearFilter,
                    child: const Text('清除筛选'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// 拖动头部区改变面板高度。换算成占屏比例后再交给 sheet 控制器，
  /// 这样滑动手感和直接拖列表一致。
  void _resizeSheet(DragUpdateDetails details) {
    if (!_sheetController.isAttached) return;
    final height = MediaQuery.sizeOf(context).height;
    if (height <= 0) return;
    final next = (_sheetController.size - details.delta.dy / height).clamp(
      _minSize,
      _maxSize,
    );
    _sheetController.jumpTo(next);
  }

  void _clearFilter() {
    _filter.clear();
    setState(() {});
  }

  /// 换源的搜索选项。Legado 把「限定作者」「加载字数」做成面板里的开关，
  /// 这里只保留真正影响结果的两个：作者过滤和按字数排序。
  Future<void> _openOptions() async {
    // 草稿副本：直接改 [_settings] 会让关闭面板时也留下未保存的勾选状态。
    var draft = _settings;
    final updated = await showModalBottomSheet<ChangeSourceSettings>(
      context: context,
      backgroundColor: _paper,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('搜索选项', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const Key('source-options-check-author'),
                  contentPadding: EdgeInsets.zero,
                  value: draft.checkAuthor,
                  title: const Text('只保留同一作者'),
                  subtitle: const Text('作者写法不同的书源会被排除'),
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(checkAuthor: value),
                  ),
                ),
                SwitchListTile(
                  key: const Key('source-options-sort-word-count'),
                  contentPadding: EdgeInsets.zero,
                  value: draft.sortByWordCount,
                  title: const Text('按字数排序'),
                  subtitle: const Text('内容更完整的书源排在前面'),
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(sortByWordCount: value),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    key: const Key('source-options-done'),
                    onPressed: () => Navigator.pop(context, draft),
                    child: const Text('完成'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (updated == null || !mounted) return;
    await widget.controller.updateChangeSourceSettings(updated);
    setState(() => _settings = updated);
    // 过滤条件变了就必须重搜：作者过滤发生在收集候选时，不能只重排现有列表。
    await _reload();
  }

  String _candidateChapterDescription(SourceCandidateInfo? info) {
    final mappedIndex = info?.mappedChapterIndex;
    if (mappedIndex == null) {
      return info?.errorMessage == null ? '章节：正在加载信息…' : '章节：暂未获取';
    }
    final chapterLabel = info?.chapterCount == null
        ? '第 ${mappedIndex + 1} 章'
        : '第 ${mappedIndex + 1}/${info!.chapterCount} 章';
    final title = info?.mappedChapterTitle?.trim() ?? '';
    return title.isEmpty ? '章节：$chapterLabel' : '章节：$chapterLabel · $title';
  }

  String _candidateWordCountDescription(SourceCandidateInfo? info) {
    final wordCount = info?.wordCount;
    if (wordCount != null) return '字数：$wordCount';
    return info?.errorMessage == null ? '字数：正在加载…' : '字数：暂未获取';
  }

  Widget _candidateRow(Book candidate) {
    final switching = _switchingId == candidate.id;
    final info = _result?.infoFor(candidate);
    final sourceId = candidate.sourceId;
    final isCurrent = sourceId != null && sourceId == widget.book.sourceId;
    final ready = info?.isReadyForDisplay ?? false;
    final accent = isCurrent ? _currentInk : _candidateInk;
    final radius = BorderRadius.circular(9);
    return Container(
      decoration: BoxDecoration(
        color: isCurrent ? _currentSurface : _surface,
        borderRadius: radius,
        border: Border.all(color: isCurrent ? _currentLine : _candidateLine),
      ),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: Key('source-candidate-${candidate.id}'),
                borderRadius: radius,
                onTap: _switchingId == null ? () => _switch(candidate) : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              candidate.sourceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: accent,
                              ),
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(width: 6),
                            const _SourceRowTag(
                              text: '当前',
                              background: Color(0xFFE5EFFD),
                              color: Color(0xFF5886C0),
                            ),
                          ],
                          if (_settings.sortByWordCount) ...[
                            const SizedBox(width: 6),
                            const _SourceRowTag(
                              text: '同字数优先',
                              background: Color(0xFFF2F4F7),
                              color: Color(0xFFA4ADBA),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '作者：${candidate.author}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: _authorInk),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _candidateChapterDescription(info),
                        key: Key('source-candidate-chapter-${candidate.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: _authorInk),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _candidateWordCountDescription(info),
                        key: Key('source-candidate-word-count-${candidate.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: ready ? FontWeight.w500 : FontWeight.w400,
                          color: ready
                              ? const Color(0xFF57759A)
                              : const Color(0xFF96A3B4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: switching
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _candidateSourceMenu(candidate),
          ),
        ],
      ),
    );
  }

  static const _candidateLine = Color(0xFFE9EDF3);
  static const _currentLine = Color(0xFFC7D9F2);
  static const _currentSurface = Color(0xFFF5F9FF);
  static const _candidateInk = Color(0xFF4D5C70);
  static const _currentInk = Color(0xFF4475B7);
  static const _authorInk = Color(0xFF8D99A9);

  /// 源级操作：换源时发现某个源不可用，就地置顶/置底/停用/删除，
  /// 不必退出面板再去书源页找它（Legado 的换源列表同样提供这四项）。
  Widget _candidateSourceMenu(Book candidate) {
    final sourceId = candidate.sourceId;
    if (sourceId == null) return const SizedBox.shrink();
    final installed = widget.controller.sources.any(
      (source) => source.id == sourceId,
    );
    if (!installed) return const SizedBox.shrink();
    return PopupMenuButton<CandidateSourceAction>(
      key: Key('source-candidate-menu-${candidate.id}'),
      tooltip: '书源操作',
      enabled: _switchingId == null,
      padding: EdgeInsets.zero,
      icon: const Icon(DesignIcons.ellipsis, size: 20, color: AppColors.muted),
      onSelected: (action) => unawaited(_sourceAction(candidate, action)),
      itemBuilder: (_) => const [
        PopupMenuItem(value: CandidateSourceAction.top, child: Text('置顶书源')),
        PopupMenuItem(value: CandidateSourceAction.bottom, child: Text('置底书源')),
        PopupMenuItem(
          value: CandidateSourceAction.disable,
          child: Text('停用书源'),
        ),
        PopupMenuItem(value: CandidateSourceAction.delete, child: Text('删除书源')),
      ],
    );
  }

  Future<void> _sourceAction(
    Book candidate,
    CandidateSourceAction action,
  ) async {
    final sourceId = candidate.sourceId;
    if (sourceId == null) return;
    if (action == CandidateSourceAction.delete) {
      final name = candidate.sourceLabel;
      final confirmed = await confirmRemoval(
        context,
        '移除“$name”？',
        '已缓存的书籍仍可阅读，新的章节需要重新导入书源才能获取。',
      );
      if (!confirmed || !mounted) return;
    }
    final kept = await widget.controller.applyCandidateSourceAction(
      sourceId,
      action,
    );
    if (!mounted) return;
    if (!kept) {
      setState(() {
        _result = _result?.withoutSource(sourceId);
        _error = null;
      });
      showMessage(context, '已删除该书源。');
      return;
    }
    if (action == CandidateSourceAction.disable) {
      // 停用的书源不再参与换源，行必须立刻消失，否则用户会以为操作没生效。
      setState(() => _result = _result?.withoutSource(sourceId));
      showMessage(context, '已停用该书源。');
      return;
    }
    setState(() {});
    showMessage(
      context,
      action == CandidateSourceAction.top ? '已置顶该书源。' : '已置底该书源。',
    );
  }
}

/// 候选行里的小标签（「当前」「同字数优先」），对应设计稿的
/// `.source-current-label` 与 `.source-pin-label`。
class _SourceRowTag extends StatelessWidget {
  const _SourceRowTag({
    required this.text,
    required this.background,
    required this.color,
  });

  final String text;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text, style: TextStyle(fontSize: 9, color: color)),
    );
  }
}

/// 换源面板的取景范围，对应筛选胶囊。
enum _SourceScope { all, sameGroup, online }
