import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../design_icons.dart';
import '../theme.dart';
import 'common.dart';

class ReaderCacheCleanupSheet extends StatefulWidget {
  const ReaderCacheCleanupSheet({
    super.key,
    required this.controller,
    required this.book,
  });

  final AppController controller;
  final Book book;

  @override
  State<ReaderCacheCleanupSheet> createState() =>
      _ReaderCacheCleanupSheetState();
}

class _ReaderCacheCleanupSheetState extends State<ReaderCacheCleanupSheet> {
  final _selected = <int>{};
  bool _busy = false;
  int? _cleared;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_reconcile);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_reconcile);
    super.dispose();
  }

  void _reconcile() {
    if (!mounted || _busy || _selected.isEmpty) return;
    final current = widget.controller.book(widget.book.id);
    final eligible = _matchesBinding(current)
        ? widget.controller
              .clearableCachedChapterIndices(widget.book.id)
              .toSet()
        : <int>{};
    if (_selected.every(eligible.contains)) return;
    setState(() {
      _selected.removeWhere((index) => !eligible.contains(index));
      _cleared = null;
      _error = '可清理章节或选择已变化，请重新确认。';
    });
  }

  bool _matchesBinding(Book? current) {
    if (current == null ||
        current.sourceId != widget.book.sourceId ||
        current.url != widget.book.url ||
        current.chapters.length != widget.book.chapters.length) {
      return false;
    }
    for (var index = 0; index < current.chapters.length; index++) {
      if (current.chapters[index].id != widget.book.chapters[index].id ||
          current.chapters[index].url != widget.book.chapters[index].url) {
        return false;
      }
    }
    return true;
  }

  void _toggle(int index, bool included) {
    if (_busy) return;
    if (included && _selected.length >= 5) {
      setState(() => _error = '每次最多清理 5 章，请先取消其他选择。');
      return;
    }
    setState(() {
      if (included) {
        _selected.add(index);
      } else {
        _selected.remove(index);
      }
      _error = null;
      _cleared = null;
    });
  }

  Future<void> _clear() async {
    if (_busy || _selected.isEmpty) return;
    final indices = _selected.toList()..sort();
    if (!await confirmRemoval(
      context,
      '清理 ${indices.length} 章缓存？',
      '将移除 ${indices.length} 章的本地正文；若书源不可达，可能无法重新下载。阅读进度与笔记保留。',
    )) {
      return;
    }
    if (!mounted) return;
    final current = widget.controller.book(widget.book.id);
    final eligible = _matchesBinding(current)
        ? widget.controller
              .clearableCachedChapterIndices(widget.book.id)
              .toSet()
        : <int>{};
    if (_selected.length != indices.length ||
        !_selected.containsAll(indices) ||
        indices.any((index) => !eligible.contains(index))) {
      setState(() {
        _selected.removeWhere((index) => !eligible.contains(index));
        _error = '可清理章节或选择已变化，请重新确认。';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _cleared = null;
    });
    try {
      final cleared = await widget.controller.clearCachedChapters(
        widget.book.id,
        indices,
        expectedBook: widget.book,
      );
      if (mounted) {
        setState(() {
          _selected.clear();
          _cleared = cleared;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reconcile();
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final current = widget.controller.book(widget.book.id);
      final valid = _matchesBinding(current);
      final eligible = valid
          ? widget.controller.clearableCachedChapterIndices(widget.book.id)
          : const <int>[];
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .8,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '管理缓存',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        key: const Key('cache-clear-close'),
                        tooltip: '关闭',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(DesignIcons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    valid
                        ? '可清理 ${eligible.length} / ${current!.cachedChapters} 章已缓存'
                        : '书籍来源或目录已变化，请关闭后重新打开。',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '当前阅读章、带书签的章节及正在下载的章节不可清理。每次最多选择 5 章。',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  if (eligible.isEmpty)
                    const Text(
                      '没有可安全清理的缓存章节。',
                      style: TextStyle(color: AppColors.muted),
                    )
                  else
                    SizedBox(
                      height: math.min(320.0, eligible.length * 56.0),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: eligible.length,
                        itemBuilder: (context, offset) {
                          final index = eligible[offset];
                          return CheckboxListTile(
                            key: Key('cache-clear-chapter-$index'),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: AppColors.blue,
                            title: Text(
                              current!.chapters[index].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('第 ${index + 1} 章 · 已缓存'),
                            value: _selected.contains(index),
                            onChanged: _busy
                                ? null
                                : (value) => _toggle(index, value!),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 18),
                  FilledButton(
                    key: const Key('cache-clear-confirm'),
                    onPressed: _busy || !valid || _selected.isEmpty
                        ? null
                        : _clear,
                    child: Text(_busy ? '正在清理…' : '清理 ${_selected.length} 章缓存'),
                  ),
                  if (_cleared != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('已清理 $_cleared 章'),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        key: const Key('cache-clear-error'),
                        style: const TextStyle(color: Color(0xFFB54444)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
