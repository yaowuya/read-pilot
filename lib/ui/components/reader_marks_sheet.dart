import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/reader_mark.dart';
import '../theme.dart';
import 'common.dart';

enum _ReaderMarkFilter { all, active, stale }

class ReaderMarksSheet extends StatefulWidget {
  const ReaderMarksSheet({
    super.key,
    required this.controller,
    required this.bookId,
    required this.onOpen,
  });

  final AppController controller;
  final String bookId;
  final ValueChanged<ReaderMarkLocation> onOpen;

  @override
  State<ReaderMarksSheet> createState() => _ReaderMarksSheetState();
}

class _ReaderMarksSheetState extends State<ReaderMarksSheet> {
  var _filter = _ReaderMarkFilter.all;
  String? _deletingId;

  Color _color(ReaderMarkColor color) => switch (color) {
    ReaderMarkColor.amber => const Color(0xFFF3D77A),
    ReaderMarkColor.mint => const Color(0xFF9AD7BE),
    ReaderMarkColor.blue => const Color(0xFFAFCBEE),
  };

  String _filterLabel(_ReaderMarkFilter filter) => switch (filter) {
    _ReaderMarkFilter.all => '全部',
    _ReaderMarkFilter.active => '可跳转',
    _ReaderMarkFilter.stale => '已失效',
  };

  Future<void> _delete(ReaderMark mark) async {
    if (_deletingId != null) return;
    if (!await confirmRemoval(
      context,
      '删除这条段落标注？',
      '只移除本机标注和备注，不会修改正文、书签或阅读进度。',
    )) {
      return;
    }
    setState(() => _deletingId = mark.id);
    try {
      await widget.controller.deleteReaderMark(mark.id);
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final entries = [
          for (final mark in widget.controller.readerMarks(widget.bookId))
            (mark: mark, location: widget.controller.readerMarkLocation(mark)),
        ];
        final visible = [
          for (final entry in entries)
            if (_filter == _ReaderMarkFilter.all ||
                (_filter == _ReaderMarkFilter.active &&
                    entry.location != null) ||
                (_filter == _ReaderMarkFilter.stale && entry.location == null))
              entry,
        ];
        final height = math.min(640.0, MediaQuery.sizeOf(context).height * .72);
        return SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('段落标注管理', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  '只管理当前书的本机段落标注；正文或来源变化后，旧标注不会跳转到其他内容。',
                  style: TextStyle(color: AppColors.muted, height: 1.7),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final filter in _ReaderMarkFilter.values)
                      ChoiceChip(
                        key: Key('reader-mark-manager-filter-${filter.name}'),
                        label: Text(_filterLabel(filter)),
                        selected: _filter == filter,
                        onSelected: _deletingId == null
                            ? (_) => setState(() => _filter = filter)
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: EmptyState(
                            title: entries.isEmpty
                                ? '这里还没有段落标注'
                                : '没有符合当前筛选的标注',
                            description: entries.isEmpty
                                ? '阅读时可从阅读设置为当前段落添加本机标注。'
                                : '切换筛选可查看当前书的其他本机标注。',
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: visible.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final entry = visible[index];
                            final mark = entry.mark;
                            final location = entry.location;
                            final preview =
                                mark.selectedText ??
                                location?.paragraph ??
                                '正文、章节或来源已变化。';
                            final deleting = _deletingId == mark.id;
                            return QuietPanel(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: _color(mark.color),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          location == null
                                              ? '已失效的段落标注'
                                              : location.chapterTitle,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (location == null)
                                        const Icon(
                                          Icons.link_off_outlined,
                                          size: 18,
                                          color: AppColors.muted,
                                        ),
                                    ],
                                  ),
                                  if (mark.selectedText != null) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      '选区标注',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Text(
                                    preview,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      height: 1.65,
                                    ),
                                  ),
                                  if (mark.note.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      '备注：${mark.note}',
                                      style: const TextStyle(height: 1.6),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (location != null)
                                        TextButton.icon(
                                          key: Key(
                                            'reader-mark-manager-open-${mark.id}',
                                          ),
                                          onPressed: deleting
                                              ? null
                                              : () => widget.onOpen(location),
                                          icon: const Icon(
                                            Icons.menu_book_outlined,
                                            size: 18,
                                          ),
                                          label: const Text('回到段落'),
                                        )
                                      else
                                        const Text(
                                          '无法回到段落',
                                          style: TextStyle(
                                            color: AppColors.muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      const SizedBox(width: 8),
                                      TextButton(
                                        key: Key(
                                          'reader-mark-manager-delete-${mark.id}',
                                        ),
                                        onPressed: _deletingId == null
                                            ? () => _delete(mark)
                                            : null,
                                        child: Text(deleting ? '正在删除…' : '删除'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
