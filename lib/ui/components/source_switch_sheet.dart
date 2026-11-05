import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../domain/change_source_settings.dart';
import '../../domain/source_switch_candidate.dart';
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

  List<Book> get _visibleCandidates {
    final query = _filter.text.trim().toLowerCase();
    final result = _result;
    // A row is listed as soon as a source returned this title: the mapped
    // chapter and word count are extra detail that streams in afterwards, so
    // they must never gate the list itself.
    final ranked = (result?.candidates ?? const <Book>[]).indexed
        .where(
          (entry) =>
              entry.$2.sourceLabel.toLowerCase().contains(query) ||
              entry.$2.author.toLowerCase().contains(query),
        )
        .toList();
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

  String get _currentChapterDescription {
    final chapters = widget.book.chapters;
    if (chapters.isEmpty) return '当前章节：目录尚未加载';
    final index = widget.book.position.chapterIndex
        .clamp(0, chapters.length - 1)
        .toInt();
    final title = chapters[index].title.trim();
    return title.isEmpty
        ? '当前章节：第 ${index + 1} 章'
        : '当前章节：第 ${index + 1} 章 · $title';
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
    // 换源是半屏操作：上方留出正文，用户能一边看当前页一边挑书源。
    final height = (MediaQuery.sizeOf(context).height - keyboard) * .66;
    return ColoredBox(
      color: _paper,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SizedBox(
            height: height,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            '换源',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '刷新候选',
                        onPressed: !_loading && _switchingId == null
                            ? () => _reload(manual: true)
                            : null,
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: _switchingId == null
                            ? () => Navigator.pop(context)
                            : null,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.book.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '当前书源：${widget.book.sourceLabel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _currentChapterDescription,
                                key: const Key('source-switch-current-chapter'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.muted,
                                ),
                              ),
                              if (result?.fromCache ?? false) ...[
                                const SizedBox(height: 10),
                                QuietPanel(
                                  key: const Key('source-switch-cache-status'),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.history,
                                        size: 16,
                                        color: AppColors.muted,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '已恢复上次加载的书源，10 天内可直接选择。',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              TextField(
                                key: const Key('source-switch-filter'),
                                controller: _filter,
                                enabled: _switchingId == null,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: '筛选书源或作者',
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: 20,
                                  ),
                                  fillColor: _surface,
                                  isDense: true,
                                  suffixIcon: _filter.text.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: '清除筛选',
                                          onPressed: _clearFilter,
                                          icon: const Icon(
                                            Icons.close,
                                            size: 18,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  key: const Key('source-switch-status'),
                  padding: const EdgeInsets.fromLTRB(20, 0, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _statusText(
                              result,
                              candidates,
                              sourceCount,
                              filtering,
                            ),
                            maxLines: 2,
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
                        onPressed: _switchingId == null ? _openOptions : null,
                        icon: Icon(
                          _settings.checkAuthor || _settings.sortByWordCount
                              ? Icons.tune
                              : Icons.tune_outlined,
                          size: 20,
                          color:
                              _settings.checkAuthor || _settings.sortByWordCount
                              ? AppColors.ink
                              : AppColors.muted,
                        ),
                      ),
                      PopupMenuButton<bool>(
                        key: const Key('source-switch-sort'),
                        tooltip: '排序',
                        enabled: !_loading && _switchingId == null,
                        onSelected: (value) =>
                            setState(() => _sortBySource = value),
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
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sort, size: 18),
                              const SizedBox(width: 6),
                              Text(_sortBySource ? '书源名称' : '相关度'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    key: const Key('source-switch-error'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: QuietPanel(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
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
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  // 已经有候选在列就不压转圈：下面的列表会随着书源返回继续增长，
                  // 上方的进度文字负责表达还在搜索。
                  child: _loading && candidates.isEmpty
                      ? const Center(
                          key: Key('source-switch-loading'),
                          child: CircularProgressIndicator(),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: candidates.length + 1,
                          itemBuilder: (context, index) => index == 0
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (result != null &&
                                        result.failedSources > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: Text(
                                          '${result.failedSources} 个书源暂时不可用，'
                                          '搜索结果可能不完整。',
                                          key: const Key(
                                            'source-switch-partial-error',
                                          ),
                                          style: const TextStyle(
                                            color: Color(0xFF765B25),
                                          ),
                                        ),
                                      ),
                                    if (result != null && candidates.isEmpty)
                                      Padding(
                                        key: Key(
                                          filtering
                                              ? 'source-switch-filter-empty'
                                              : 'source-switch-empty',
                                        ),
                                        padding: const EdgeInsets.all(24),
                                        child: Column(
                                          children: [
                                            Text(
                                              filtering
                                                  ? '没有匹配的书源或作者。'
                                                  : result.failedSources > 0
                                                  ? '暂未找到候选，部分书源未能完成搜索。'
                                                  : '没有找到其他同名书源。',
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
                                )
                              : Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _candidateRow(candidates[index - 1]),
                                ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: Key('source-candidate-${candidate.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: _switchingId == null ? () => _switch(candidate) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(
                book: candidate,
                imageLoader: widget.controller.loadBookCover,
                width: 48,
                height: 70,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.sourceLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      candidate.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '作者：${candidate.author}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _candidateChapterDescription(info),
                      key: Key('source-candidate-chapter-${candidate.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    Text(
                      _candidateWordCountDescription(info),
                      key: Key('source-candidate-word-count-${candidate.id}'),
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
              const SizedBox(width: 8),
              if (switching)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _candidateSourceMenu(candidate),
                    const Icon(Icons.chevron_right, color: AppColors.muted),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

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
      icon: const Icon(Icons.more_vert, size: 20, color: AppColors.muted),
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
