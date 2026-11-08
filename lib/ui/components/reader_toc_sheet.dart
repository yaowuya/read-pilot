import 'package:flutter/material.dart';

import '../../domain/book.dart';
import '../theme.dart';
import 'book_cover.dart';
import 'common.dart';
import 'design.dart';

/// Chapter directory following the draft: cover intro, chapter search, a
/// catalog/bookmark tab bar and the cache-status footnote.
///
/// Reorders only the display; selection always returns a Book.chapters index.
class ReaderTocSheet extends StatefulWidget {
  const ReaderTocSheet({
    super.key,
    required this.book,
    required this.currentChapterIndex,
    required this.descending,
    required this.onOrderChanged,
    required this.onChapterSelected,
    this.bookmarks = const [],
  });

  final Book book;
  final int currentChapterIndex;
  final bool descending;
  final Future<void> Function(bool) onOrderChanged;
  final ValueChanged<int> onChapterSelected;

  /// Optional local bookmarks; the bookmark tab falls back to the designed
  /// empty state when the reader does not pass them.
  final List<Bookmark> bookmarks;

  @override
  State<ReaderTocSheet> createState() => _ReaderTocSheetState();
}

class _ReaderTocSheetState extends State<ReaderTocSheet> {
  late bool _descending = widget.descending;
  final _search = TextEditingController();
  bool _saving = false;
  bool _catalog = true;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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

  bool _matches(String title) {
    final query = _query.trim().toLowerCase();
    return query.isEmpty || title.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .88,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _header(context),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _catalog ? _catalogBody() : _bookmarksBody(),
          ),
        ),
        _footnote(),
      ],
    ),
  );

  Widget _header(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text('目录', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          Text(
            _saving
                ? '保存中…'
                : '${widget.book.chapters.length} 章 · ${_descending ? '倒序' : '正序'}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
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
      _intro(),
      const SizedBox(height: 16),
      SearchPill(
        hintText: '搜索章节名称',
        controller: _search,
        onChanged: (value) => setState(() => _query = value),
        fieldKey: const Key('toc-search-field'),
      ),
      const SizedBox(height: 4),
      _tabs(),
    ],
  );

  Widget _intro() {
    final chapters = widget.book.chapters;
    final cached = chapters.where((chapter) => chapter.isCached).length;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          BookCover(book: widget.book, width: 45, height: 65),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '共 ${chapters.length} 章 · $cached 章已缓存',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFA0A7B1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs() => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFECEEF3))),
    ),
    child: Row(
      children: [
        _TocTab(
          key: const Key('toc-tab-catalog'),
          label: '目录',
          active: _catalog,
          onTap: () => setState(() => _catalog = true),
        ),
        const SizedBox(width: 22),
        _TocTab(
          key: const Key('toc-tab-bookmarks'),
          label: '书签',
          active: !_catalog,
          onTap: () => setState(() => _catalog = false),
        ),
        const Spacer(),
        InkWell(
          key: const Key('toc-current'),
          onTap: () => widget.onChapterSelected(widget.currentChapterIndex),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Row(
              children: [
                Text(
                  '当前章节',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8E97A4)),
                ),
                SizedBox(width: 4),
                Icon(Icons.my_location, size: 14, color: Color(0xFF8E97A4)),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _catalogBody() {
    final chapters = widget.book.chapters;
    if (chapters.isEmpty) {
      return const _TocEmpty(title: '还没有章节', hint: '打开目录后可尝试重新获取章节列表');
    }
    final rows = <Widget>[];
    for (var display = 0; display < chapters.length; display++) {
      final index = _descending ? chapters.length - 1 - display : display;
      final chapter = chapters[index];
      if (!_matches(chapter.title)) continue;
      rows.add(
        KeyedSubtree(
          key: ValueKey('toc-row-$index'),
          child: _chapterRow(index, chapter),
        ),
      );
    }
    if (rows.isEmpty) return const _TocEmpty(title: '没有找到这个章节');
    return Column(children: rows);
  }

  Widget _chapterRow(int index, Chapter chapter) {
    final current = index == widget.currentChapterIndex;
    return ListTile(
      key: ValueKey('toc-chapter-$index'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      minLeadingWidth: 18,
      horizontalTitleGap: 14,
      selected: current,
      selectedTileColor: AppColors.softBlue,
      leading: SizedBox(
        width: 18,
        child: Text(
          (index + 1).toString().padLeft(2, '0'),
          style: TextStyle(
            fontSize: 10,
            color: current ? AppColors.blue : const Color(0xFFB4BAC4),
          ),
        ),
      ),
      title: Text(
        chapter.title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: current ? FontWeight.w600 : FontWeight.w400,
          color: current ? AppColors.blue : AppColors.ink,
        ),
      ),
      trailing: current
          ? const Icon(Icons.graphic_eq, size: 17, color: AppColors.blue)
          : (chapter.isCached
                ? const Icon(
                    Icons.offline_pin_outlined,
                    size: 17,
                    color: AppColors.muted,
                  )
                : const Icon(
                    Icons.check_circle_outline,
                    size: 17,
                    color: Color(0xFFBCC4CE),
                  )),
      onTap: _saving ? null : () => widget.onChapterSelected(index),
    );
  }

  Widget _bookmarksBody() {
    final items = widget.bookmarks
        .where((bookmark) => bookmark.bookId == widget.book.id)
        .toList();
    if (items.isEmpty) {
      return const _TocEmpty(title: '还没有书签', hint: '长按章节或划线可以收藏');
    }
    final chapters = widget.book.chapters;
    return Column(
      children: [
        for (final bookmark in items)
          InkWell(
            key: ValueKey('toc-bookmark-${bookmark.id}'),
            onTap: _saving
                ? null
                : () => widget.onChapterSelected(bookmark.chapterIndex),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF1F2F5))),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.bookmark_outlined,
                    size: 16,
                    color: AppColors.blue,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bookmark.chapterIndex >= 0 &&
                                  bookmark.chapterIndex < chapters.length
                              ? chapters[bookmark.chapterIndex].title
                              : '第 ${bookmark.chapterIndex + 1} 章',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bookmark.note.isEmpty ? '书签' : bookmark.note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFA0A7B1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _footnote() => Padding(
    key: const Key('toc-note'),
    padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
    child: const Row(
      children: [
        Icon(Icons.download_outlined, size: 13, color: Color(0xFFA7ADB7)),
        SizedBox(width: 5),
        Expanded(
          child: Text(
            '章节列表用于展示当前、已读与缓存状态。',
            style: TextStyle(
              fontSize: 10,
              height: 1.7,
              color: Color(0xFFA7ADB7),
            ),
          ),
        ),
      ],
    ),
  );
}

class _TocTab extends StatelessWidget {
  const _TocTab({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: active ? AppColors.blue : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: active ? const Color(0xFF3D444F) : const Color(0xFFA1A7B1),
        ),
      ),
    ),
  );
}

class _TocEmpty extends StatelessWidget {
  const _TocEmpty({required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 15),
    child: Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Color(0xFF9098A5)),
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              height: 1.8,
              color: Color(0xFFB0B7C1),
            ),
          ),
        ],
      ],
    ),
  );
}
