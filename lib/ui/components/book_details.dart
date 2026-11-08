import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../theme.dart';
import 'book_cover.dart';
import 'book_text_rule_sheet.dart';
import 'common.dart';
import 'design.dart';
import 'reader_cache_cleanup_sheet.dart';
import 'reader_cache_sheet.dart';
import 'reading_assistant_sheet.dart';
import 'source_switch_sheet.dart';

enum _DetailAction { switchSource, refreshCover, cache, manageCache, textRules }

class BookDetails extends StatefulWidget {
  const BookDetails({
    super.key,
    required this.book,
    required this.controller,
    required this.onRead,
    this.onOpenNotes,
  });

  final Book book;
  final AppController controller;
  final ValueChanged<Book> onRead;

  /// 设计稿把「我的笔记」作为详情页的一行入口；没有回调时这一行只显示条数。
  final VoidCallback? onOpenNotes;

  @override
  State<BookDetails> createState() => _BookDetailsState();
}

class _BookDetailsState extends State<BookDetails> {
  String? _busyAction;
  String? _error;
  bool _introExpanded = false;
  Book? _replacement;

  /// 未加入书架的书换源后只存在于内存里，父级仍持有旧对象，因此这里自己记住
  /// 换源结果，否则抽屉关掉后又显示回旧书源。
  Book _resolveBook(Book? shelfBook) =>
      shelfBook ?? _replacement ?? widget.book;

  Future<void> _refreshCover(Book book) async {
    if (_busyAction != null) return;
    setState(() {
      _busyAction = 'cover';
      _error = null;
    });
    try {
      await widget.controller.refreshBookCover(book.id);
      if (mounted) showMessage(context, '封面已刷新。');
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _changeSource(Book book) async {
    if (_busyAction != null) return;
    final switched = await showModalBottomSheet<Book>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF1EDE1),
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) =>
          SourceSwitchSheet(controller: widget.controller, book: book),
    );
    if (mounted && switched != null) {
      setState(() {
        _error = null;
        _replacement = switched;
      });
      showMessage(context, '已切换到 ${switched.sourceLabel}。');
    }
  }

  void _cacheChapters(Book book) {
    if (_busyAction != null || book.chapters.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.background,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) =>
          ReaderCacheSheet(controller: widget.controller, book: book),
    );
  }

  void _manageCache(Book book) {
    if (_busyAction != null || book.cachedChapters == 0) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.background,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) =>
          ReaderCacheCleanupSheet(controller: widget.controller, book: book),
    );
  }

  void _manageTextRules(Book book) {
    if (_busyAction != null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.background,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) =>
          BookTextRuleSheet(controller: widget.controller, book: book),
    );
  }

  Future<void> _read(Book book) async {
    if (_busyAction != null) return;
    setState(() {
      _busyAction = 'read';
      _error = null;
    });
    try {
      final added = await widget.controller.addBook(book);
      if (mounted) {
        Navigator.pop(context);
        widget.onRead(added);
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _addToShelf(Book book) async {
    if (_busyAction != null) return;
    setState(() {
      _busyAction = 'shelf';
      _error = null;
    });
    try {
      await widget.controller.addBook(book);
      if (mounted) showMessage(context, '《${book.title}》已加入书架。');
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  /// 设计稿把换源、刷新封面、缓存与正文替换收进「更多」，书封旁不再堆按钮。
  Widget _moreMenu(Book book, Book? shelfBook) {
    final entries = <_DetailAction>[
      // 换源对网络书一律可用：还没加入书架的搜索结果也能先换源再决定是否上架。
      if (book.isRemote) _DetailAction.switchSource,
      if (shelfBook != null) ...[
        if (book.isRemote) ...[
          _DetailAction.refreshCover,
          // 本地书的段落就是正文本身，清缓存等于删正文，所以只对网络书开放。
          if (book.chapters.isNotEmpty) _DetailAction.cache,
          if (book.cachedChapters > 0) _DetailAction.manageCache,
        ],
        _DetailAction.textRules,
      ],
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<_DetailAction>(
      key: const Key('book-more'),
      tooltip: '更多操作',
      onSelected: (action) => switch (action) {
        _DetailAction.switchSource => _changeSource(book),
        _DetailAction.refreshCover => _refreshCover(book),
        _DetailAction.cache => _cacheChapters(book),
        _DetailAction.manageCache => _manageCache(book),
        _DetailAction.textRules => _manageTextRules(book),
      },
      itemBuilder: (context) => [
        for (final action in entries)
          PopupMenuItem<_DetailAction>(
            key: Key(_actionKey(action)),
            value: action,
            child: Row(
              children: [
                Icon(_actionIcon(action), size: 18, color: AppColors.muted),
                const SizedBox(width: 10),
                Text(_actionLabel(action)),
              ],
            ),
          ),
      ],
      child: const _CircleToolButton(icon: Icons.more_horiz, tooltip: '更多操作'),
    );
  }

  String _actionKey(_DetailAction action) => switch (action) {
    _DetailAction.switchSource => 'book-change-source',
    _DetailAction.refreshCover => 'book-refresh-cover',
    _DetailAction.cache => 'book-cache-chapters',
    _DetailAction.manageCache => 'book-manage-cache',
    _DetailAction.textRules => 'book-text-rules',
  };

  IconData _actionIcon(_DetailAction action) => switch (action) {
    _DetailAction.switchSource => Icons.swap_horiz,
    _DetailAction.refreshCover => Icons.image_search_outlined,
    _DetailAction.cache => Icons.download_for_offline_outlined,
    _DetailAction.manageCache => Icons.delete_sweep_outlined,
    _DetailAction.textRules => Icons.text_fields,
  };

  String _actionLabel(_DetailAction action) => switch (action) {
    _DetailAction.switchSource => '换源',
    _DetailAction.refreshCover => '刷新封面',
    _DetailAction.cache => '缓存章节',
    _DetailAction.manageCache => '管理缓存',
    _DetailAction.textRules => '正文替换',
  };

  Widget _hero(Book book, Book? shelfBook) => Stack(
    clipBehavior: Clip.none,
    children: [
      Row(
        children: [
          BookCover(
            book: book,
            imageLoader: widget.controller.loadBookCover,
            width: 107,
            height: 157,
          ),
          const SizedBox(width: 23),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 23,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  book.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF858D99),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${book.category} · ${book.isExcerpt ? '公版节选' : '文字阅读'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9CA4AF),
                  ),
                ),
                const SizedBox(height: 13),
                PillTag(
                  book.sourceLabel,
                  icon: book.isRemote
                      ? Icons.public
                      : Icons.description_outlined,
                ),
              ],
            ),
          ),
        ],
      ),
      Positioned(top: -14, right: -10, child: _moreMenu(book, shelfBook)),
    ],
  );

  Widget _metrics(Book book) => Container(
    margin: const EdgeInsets.only(top: 23),
    padding: const EdgeInsets.symmetric(vertical: 18),
    decoration: const BoxDecoration(
      border: Border(
        top: BorderSide(color: AppColors.line),
        bottom: BorderSide(color: AppColors.line),
      ),
    ),
    child: Row(
      children: [
        _DetailMetric(
          value: book.chapters.isEmpty ? '待加载' : '${book.chapters.length} 章',
          label: book.isRemote ? '目录来源' : '本地正文',
        ),
        _DetailMetric(
          value: '${(book.progress * 100).round()}%',
          label: '阅读进度',
        ),
        _DetailMetric(
          value: book.finished
              ? '已读完'
              : book.hasStarted
              ? '在读'
              : '未读',
          label: '正文状态',
        ),
      ],
    ),
  );

  Widget _intro(Book book) {
    final text = book.description.isEmpty
        ? '书源未提供简介。添加后会按需加载目录与正文。'
        : book.description;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('关于这本书'),
        Text(
          text,
          key: const Key('book-intro'),
          maxLines: _introExpanded ? null : 4,
          overflow: _introExpanded ? null : TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            height: 2,
            color: Color(0xFF777F8C),
          ),
        ),
        TextButton(
          key: const Key('book-intro-toggle'),
          onPressed: () => setState(() => _introExpanded = !_introExpanded),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 36),
            foregroundColor: const Color(0xFF99A2B0),
            textStyle: const TextStyle(fontSize: 11),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_introExpanded ? '收起' : '展开简介'),
              Icon(
                _introExpanded ? Icons.expand_less : Icons.expand_more,
                size: 15,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rows(Book book) {
    final notes = widget.controller.bookmarks
        .where((note) => note.bookId == book.id)
        .length;
    return Column(
      children: [
        ListRow(
          key: const Key('book-toc-row'),
          icon: Icons.list_alt,
          title: '目录',
          subtitle: book.chapters.isEmpty
              ? '加入书架后加载'
              : '共 ${book.chapters.length} 章 · ${book.cachedChapters} 章已缓存',
        ),
        ListRow(
          key: const Key('book-notes-row'),
          icon: Icons.edit_note,
          title: '我的笔记',
          subtitle: '$notes 条想法与划线',
          onTap: widget.onOpenNotes,
        ),
      ],
    );
  }

  /// 设计稿的「读之前，先认识这本书」入口。导读只用本机已有信息——简介、章数、
  /// 已读章数与笔记条数——所以打开的是一个本地回顾面板，不连模型。
  Widget _assistantEntry(Book book, Book? shelfBook) {
    final live = shelfBook ?? book;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Material(
        color: const Color(0xFFF0F5FD),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          key: const Key('book-ai-entry'),
          borderRadius: BorderRadius.circular(9),
          onTap: () => _openAssistant(live),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: Color(0xFF6A93CC),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '读之前，先认识这本书',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4872AB),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '基于简介、目录和你的笔记，做一次本地回顾',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF91A4C0),
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 17,
                  color: Color(0xFFB0BECE),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openAssistant(Book book) {
    if (_busyAction != null) return;
    final notes = widget.controller.bookmarks
        .where((note) => note.bookId == book.id)
        .toList();
    final chapterTitle = book.chapters.isEmpty
        ? '还没有加载目录'
        : book
              .chapters[book.position.chapterIndex.clamp(
                0,
                book.chapters.length - 1,
              )]
              .title;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (_) => Theme(
        data: appTheme(),
        child: ReadingAssistantSheet(
          book: book,
          chapterTitle: chapterTitle,
          paragraph: book.description,
          readChapters: book.position.chapterIndex,
          notes: notes,
        ),
      ),
    );
  }

  Widget _sourceNote(Book book) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 13, color: Color(0xFFA7ADB7)),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            book.provenance,
            style: const TextStyle(
              fontSize: 10,
              height: 1.7,
              color: Color(0xFFA7ADB7),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _bottomBar(Book book, Book? shelfBook) => Container(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              key: const Key('book-add-shelf'),
              onPressed: _busyAction == null && shelfBook == null
                  ? () => _addToShelf(book)
                  : null,
              icon: Icon(shelfBook == null ? Icons.add : Icons.check, size: 17),
              label: Text(shelfBook == null ? '加入书架' : '已在书架'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF54749D),
                side: BorderSide.none,
                backgroundColor: const Color(0xFFF2F5FA),
                textStyle: const TextStyle(fontSize: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 48,
            child: FilledButton.icon(
              key: const Key('book-read'),
              onPressed: _busyAction == null ? () => _read(book) : null,
              icon: _busyAction == 'read'
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.menu_book_outlined, size: 18),
              label: Text(
                _busyAction == 'read'
                    ? '正在加载目录…'
                    : book.hasStarted && !book.finished
                    ? '继续阅读'
                    : '开始阅读',
              ),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final shelfBook = widget.controller.book(widget.book.id);
      final book = _resolveBook(shelfBook);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _hero(book, shelfBook),
                  _metrics(book),
                  _assistantEntry(book, shelfBook),
                  _intro(book),
                  _rows(book),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        key: const Key('book-details-error'),
                        style: const TextStyle(
                          color: Color(0xFFB54444),
                          height: 1.8,
                        ),
                      ),
                    ),
                  _sourceNote(book),
                ],
              ),
            ),
          ),
          _bottomBar(book, shelfBook),
        ],
      );
    },
  );
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF929AA5)),
        ),
      ],
    ),
  );
}

class _CircleToolButton extends StatelessWidget {
  const _CircleToolButton({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  /// The popup menu owns the gesture, so the visual below stays inert.
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Container(
      width: 34,
      height: 34,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F1F4),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: AppColors.ink),
    ),
  );
}
