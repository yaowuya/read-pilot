import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../components/book_cover.dart';
import '../components/common.dart';
import '../components/design.dart';
import '../theme.dart';

/// 设计稿 `.note-card` 一组中性色，主题色板没有收录。
const _headInk = Color(0xFF8B96A7);
const _dateInk = Color(0xFFB1B8C1);
const _quoteLine = Color(0xFFD8C083);
const _quoteInk = Color(0xFF73767E);
const _countInk = Color(0xFFA6AEB9);
const _noteInk = Color(0xFFA1A7B1);
const _bottomInk = Color(0xFFB0B7C1);
const _actionInk = Color(0xFF9EA9BA);

/// 读书笔记：按设计稿把书签与想法排成一路发丝线分隔的引文卡。
///
/// 搜索只过滤本机已有的笔记（书名、划线、想法三处任一命中），不发网络请求；
/// 从阅读器进入时带 [bookId]，仅看这一本书。导出按钮保留设计稿的位置，本版本
/// 没有导出能力，点击后如实提示，而不是假装导出了一份文件。
class NotesScreen extends StatefulWidget {
  const NotesScreen({
    super.key,
    required this.controller,
    required this.onOpen,
    this.bookId,
  });

  final AppController controller;
  final String? bookId;
  final ValueChanged<Bookmark> onOpen;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _query = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<Bookmark> get _notes {
    final keyword = _keyword.trim().toLowerCase();
    return [
      for (final note in widget.controller.bookmarks)
        if (widget.bookId == null || note.bookId == widget.bookId)
          if (keyword.isEmpty || _matches(note, keyword)) note,
    ];
  }

  bool _matches(Bookmark note, String keyword) {
    final title = widget.controller.book(note.bookId)?.title ?? '';
    return '$title${note.quote}${note.note}'.toLowerCase().contains(keyword);
  }

  /// 设计稿用「今天 10:24 / 昨天 21:16」，更早的只留日期。
  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    String two(int number) => number.toString().padLeft(2, '0');
    if (day == today) return '今天 ${two(local.hour)}:${two(local.minute)}';
    if (day == today.subtract(const Duration(days: 1))) {
      return '昨天 ${two(local.hour)}:${two(local.minute)}';
    }
    if (local.year == now.year) return '${local.month}月${local.day}日';
    return '${local.year}年${local.month}月${local.day}日';
  }

  String _chapterLabel(Bookmark note, Book? book) {
    final index = note.chapterIndex;
    if (book != null && index >= 0 && index < book.chapters.length) {
      final title = book.chapters[index].title.trim();
      if (title.isNotEmpty) return title;
    }
    return '第 ${index + 1} 章';
  }

  Future<void> _delete(Bookmark note) async {
    if (!await confirmRemoval(context, '删除这条笔记？', '这条划线与想法将从本机移除，不影响书籍正文。')) {
      return;
    }
    if (!mounted) return;
    try {
      await widget.controller.deleteBookmark(note.id);
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: appTheme(),
    child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppTopBar(
        onBack: () => Navigator.of(context).maybePop(),
        title: '读书笔记',
        actions: [
          CircleIconButton(
            key: const Key('notes-export'),
            icon: Icons.ios_share,
            tooltip: '导出笔记',
            onPressed: () => showMessage(context, '导出功能将在后续版本提供。'),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final notes = _notes;
          return ListView(
            padding: const EdgeInsets.fromLTRB(25, 14, 25, 28),
            children: [
              SearchPill(
                controller: _query,
                fieldKey: const Key('notes-search-field'),
                hintText: '搜索书名、划线或想法',
                onChanged: (value) => setState(() => _keyword = value),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 6),
                child: Text(
                  '${notes.length} 条笔记 · 只属于你的阅读痕迹',
                  key: const Key('notes-count'),
                  style: const TextStyle(fontSize: 11, color: _countInk),
                ),
              ),
              if (notes.isEmpty)
                EmptyBlock(
                  icon: Icons.edit_note,
                  title: _keyword.trim().isEmpty ? '写下第一条想法' : '没有找到相关笔记',
                  description: '阅读时，选中一句话\n就可以开始记录',
                )
              else
                for (final note in notes) _noteCard(note),
            ],
          );
        },
      ),
    ),
  );

  Widget _noteCard(Bookmark note) {
    final book = widget.controller.book(note.bookId);
    return Container(
      key: Key('note-card-${note.id}'),
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 19),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _noteCover(book),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  book?.title ?? '已移除的书籍',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _headInk),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _dateLabel(note.createdAt),
                style: const TextStyle(fontSize: 9, color: _dateInk),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: _quoteLine, width: 2)),
            ),
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              note.quote,
              style: const TextStyle(
                fontSize: 14,
                height: 1.9,
                color: _quoteInk,
              ),
            ),
          ),
          if (note.note.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              note.note,
              style: const TextStyle(
                fontSize: 12,
                height: 1.9,
                color: _noteInk,
              ),
            ),
          ],
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    key: Key('note-jump-${note.id}'),
                    onTap: book == null ? null : () => widget.onOpen(note),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _chapterLabel(note, book),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: book == null ? _bottomInk : _actionInk,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.north_east,
                            size: 15,
                            color: book == null ? _bottomInk : _actionInk,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                key: Key('note-delete-${note.id}'),
                tooltip: '删除这条笔记',
                onPressed: () => _delete(note),
                iconSize: 15,
                color: _actionInk,
                padding: const EdgeInsets.all(5),
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _noteCover(Book? book) {
    if (book == null) {
      return Container(
        width: 21,
        height: 29,
        decoration: BoxDecoration(
          color: AppColors.softBlue,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    // 设计稿封面上限 21×29，[BookCover] 的回落排版到不了这么小，先按 2 倍
    // 画出来再整体缩到目标尺寸，省得它内部的文字列溢出。
    return SizedBox(
      width: 21,
      height: 29,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: 42,
          height: 58,
          child: BookCover(
            book: book,
            imageLoader: widget.controller.loadBookCover,
            width: 42,
            height: 58,
          ),
        ),
      ),
    );
  }
}
