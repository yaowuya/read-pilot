import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../theme.dart';
import 'common.dart';

/// Shows one user-confirmed, bounded chapter cache batch.
class ReaderCacheSheet extends StatefulWidget {
  const ReaderCacheSheet({
    super.key,
    required this.controller,
    required this.book,
  });

  final AppController controller;
  final Book book;

  @override
  State<ReaderCacheSheet> createState() => _ReaderCacheSheetState();
}

class _ReaderCacheSheetState extends State<ReaderCacheSheet> {
  late final int _startIndex = widget.book.position.chapterIndex.clamp(
    0,
    math.max(0, widget.book.chapters.length - 1),
  );
  late int _count = math.min(5, widget.book.chapters.length - _startIndex);
  Completer<void>? _abort;
  ChapterCacheBatchResult? _result;
  String? _error;
  int _completed = 0;
  bool _running = false;
  bool _stopping = false;

  @override
  void dispose() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    super.dispose();
  }

  bool _matchesBinding(Book? current) {
    if (current == null ||
        current.sourceId != widget.book.sourceId ||
        current.url != widget.book.url ||
        _startIndex + _count > current.chapters.length) {
      return false;
    }
    for (var offset = 0; offset < _count; offset++) {
      final index = _startIndex + offset;
      if (current.chapters[index].id != widget.book.chapters[index].id) {
        return false;
      }
    }
    return true;
  }

  Future<void> _start() async {
    if (_running || _count < 1) return;
    if (!_matchesBinding(widget.controller.book(widget.book.id))) {
      setState(() => _error = '书籍来源或目录已变化，请关闭后重新打开。');
      return;
    }
    final abort = Completer<void>();
    setState(() {
      _abort = abort;
      _running = true;
      _stopping = false;
      _completed = 0;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.controller.cacheChapterRange(
        widget.book.id,
        startIndex: _startIndex,
        count: _count,
        abortTrigger: abort.future,
        onProgress: (completed, _) {
          if (mounted && identical(_abort, abort)) {
            setState(() => _completed = completed);
          }
        },
      );
      if (!mounted || !identical(_abort, abort)) return;
      setState(() => _result = result);
    } catch (error) {
      if (mounted && identical(_abort, abort)) {
        setState(() => _error = errorMessage(error));
      }
    } finally {
      if (mounted && identical(_abort, abort)) {
        setState(() {
          _running = false;
          _abort = null;
        });
      }
    }
  }

  void _stop() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    setState(() => _stopping = true);
  }

  @override
  Widget build(BuildContext context) {
    final maxCount = math.min(5, widget.book.chapters.length - _startIndex);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .8,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('缓存章节', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(
                  '从当前位置起最多缓存 $maxCount 章；已缓存的章节会跳过。',
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                Text(
                  '仅在你确认后顺序获取；停止只影响尚未开始的章节。',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text('缓存章节数'),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      key: const Key('reader-cache-count'),
                      value: _count > 0 ? _count : null,
                      items: [
                        for (var value = 1; value <= maxCount; value++)
                          DropdownMenuItem(
                            value: value,
                            child: Text('$value 章'),
                          ),
                      ],
                      onChanged: _running
                          ? null
                          : (value) => setState(() => _count = value!),
                    ),
                  ],
                ),
                if (_count > 0)
                  Text(
                    '${widget.book.chapters[_startIndex].title} — '
                    '${widget.book.chapters[_startIndex + _count - 1].title}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
                if (_running) ...[
                  const SizedBox(height: 20),
                  LinearProgressIndicator(
                    value: _count == 0 ? 0 : _completed / _count,
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text('$_completed / $_count'),
                  ),
                  TextButton(
                    key: const Key('reader-cache-stop'),
                    onPressed: _stopping ? null : _stop,
                    child: Text(_stopping ? '等待当前章节完成…' : '停止后续章节'),
                  ),
                ] else ...[
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('reader-cache-confirm'),
                    onPressed: _count < 1 ? null : _start,
                    child: const Text('开始缓存'),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      key: const Key('reader-cache-error'),
                      style: const TextStyle(color: Color(0xFFB54444)),
                    ),
                  ),
                if (_result case final result?) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${result.cancelled ? '已停止 · ' : ''}新增缓存 ${result.downloaded} 章 · '
                    '已有 ${result.skippedCached} 章 · '
                    '失败 ${result.failedIndices.length} 章',
                    key: const Key('reader-cache-result'),
                  ),
                  if (result.failedIndices.isNotEmpty)
                    TextButton(
                      key: const Key('reader-cache-retry'),
                      onPressed: _start,
                      child: const Text('重试未缓存章节'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
