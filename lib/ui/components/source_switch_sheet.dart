import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
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
  bool _sortBySource = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    final abort = Completer<void>();
    setState(() {
      _abort = abort;
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.controller.findSourceCandidates(
        widget.book.id,
        abortTrigger: abort.future,
      );
      if (!mounted || _abort != abort) return;
      setState(() {
        _result = result;
        _loading = false;
        _abort = null;
      });
    } catch (error) {
      if (!mounted || _abort != abort) return;
      setState(() {
        _error = errorMessage(error);
        _loading = false;
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
    final ranked = (_result?.candidates ?? const <Book>[]).indexed
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
    return ColoredBox(
      color: _paper,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SizedBox(
            height: (MediaQuery.sizeOf(context).height - keyboard) * .9,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '刷新候选',
                                onPressed: !_loading && _switchingId == null
                                    ? _load
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
                              Row(
                                children: [
                                  Expanded(
                                    child: Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        _loading
                                            ? '正在查找其他同名书源…'
                                            : result == null
                                            ? '候选搜索未完成'
                                            : filtering
                                            ? '匹配 ${candidates.length} / '
                                                  '${result.candidates.length} · '
                                                  '$sourceCount 个书源'
                                            : '候选 ${candidates.length} · '
                                                  '$sourceCount 个书源',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.muted,
                                        ),
                                      ),
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
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
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
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ],
                    ),
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
                            onPressed: _switchingId == null ? _load : null,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: _loading
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

  Widget _candidateRow(Book candidate) {
    final switching = _switchingId == candidate.id;
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
                const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
