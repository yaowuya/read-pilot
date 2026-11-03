import 'package:flutter/material.dart';

import '../../domain/book.dart';
import '../theme.dart';
import 'common.dart';

/// Reorders only the display; selection always returns a Book.chapters index.
class ReaderTocSheet extends StatefulWidget {
  const ReaderTocSheet({
    super.key,
    required this.book,
    required this.currentChapterIndex,
    required this.descending,
    required this.onOrderChanged,
    required this.onChapterSelected,
  });

  final Book book;
  final int currentChapterIndex;
  final bool descending;
  final Future<void> Function(bool) onOrderChanged;
  final ValueChanged<int> onChapterSelected;

  @override
  State<ReaderTocSheet> createState() => _ReaderTocSheetState();
}

class _ReaderTocSheetState extends State<ReaderTocSheet> {
  late bool _descending = widget.descending;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant ReaderTocSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_saving && widget.descending != oldWidget.descending) {
      _descending = widget.descending;
    }
  }

  Future<void> _toggleOrder() async {
    if (_saving) return;
    final previous = _descending;
    setState(() {
      _descending = !previous;
      _saving = true;
    });
    try {
      await widget.onOrderChanged(_descending);
    } catch (error) {
      if (mounted) {
        setState(() => _descending = previous);
        showMessage(context, errorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .65,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Row(
            children: [
              Text('目录', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              Text(
                _saving
                    ? '保存中…'
                    : '${widget.book.chapters.length} 章 · ${_descending ? '倒序' : '正序'}',
                style: const TextStyle(color: AppColors.muted),
              ),
              IconButton(
                key: const Key('reader-toc-order'),
                tooltip: _descending ? '改为正序' : '改为倒序',
                isSelected: _descending,
                onPressed: _saving ? null : _toggleOrder,
                icon: const Icon(Icons.swap_vert),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: widget.book.chapters.length,
            itemBuilder: (context, displayIndex) {
              final index = _descending
                  ? widget.book.chapters.length - 1 - displayIndex
                  : displayIndex;
              final chapter = widget.book.chapters[index];
              return ListTile(
                key: ValueKey('toc-chapter-$index'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 5,
                ),
                selected: index == widget.currentChapterIndex,
                selectedTileColor: AppColors.softBlue,
                title: Text(
                  chapter.title,
                  style: const TextStyle(fontSize: 14),
                ),
                trailing: index == widget.currentChapterIndex
                    ? const Icon(Icons.check, size: 19)
                    : (chapter.isCached
                          ? const Icon(
                              Icons.offline_pin_outlined,
                              size: 17,
                              color: AppColors.muted,
                            )
                          : null),
                onTap: _saving ? null : () => widget.onChapterSelected(index),
              );
            },
          ),
        ),
      ],
    ),
  );
}
