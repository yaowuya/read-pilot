import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../domain/shelf_group.dart';
import '../components/book_cover.dart';
import '../components/common.dart';
import '../components/shelf_group_sheets.dart';
import '../theme.dart';

/// Which layer of the shelf is on screen.
///
/// With groups the shelf is two layers, mirroring wechat reading: [cards] shows
/// one card per group and tapping a card drills into [group]. A reader without
/// any group never sees a card layer — the shelf stays the flat book grid,
/// which is what [allBooks] renders.
enum _ShelfScope { cards, allBooks, group }

/// The sort tabs above the shelf.
///
/// These replace the old 全部/在读/已读 filter chips plus a dropdown: wechat
/// reading sorts rather than filters, and 进度 lifts books being read.
enum _ShelfSort { recent, progress, title, category }

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onDetails,
    required this.onImport,
    required this.onDiscover,
  });
  final AppController controller;
  final ValueChanged<Book> onOpen;
  final ValueChanged<Book> onDetails;
  final VoidCallback onImport;
  final VoidCallback onDiscover;
  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
  String _query = '';
  _ShelfSort _sort = _ShelfSort.recent;
  _ShelfScope _scope = _ShelfScope.cards;
  String? _selectedGroupId;
  bool _list = false;

  static final _epoch = DateTime(1970);

  void _manageGroups() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.background,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (_) => ShelfGroupManagerSheet(controller: widget.controller),
  );

  void _editBookGroups(Book book) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.background,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (_) =>
        ShelfBookGroupsSheet(controller: widget.controller, bookId: book.id),
  );

  int Function(Book, Book) get _comparator => switch (_sort) {
    _ShelfSort.recent => (a, b) => (b.lastOpenedAt ?? _epoch).compareTo(
      a.lastOpenedAt ?? _epoch,
    ),
    _ShelfSort.progress => (a, b) {
      final aReading = a.hasStarted && !a.finished;
      final bReading = b.hasStarted && !b.finished;
      if (aReading != bReading) return aReading ? -1 : 1;
      final byProgress = b.progress.compareTo(a.progress);
      return byProgress != 0 ? byProgress : a.title.compareTo(b.title);
    },
    _ShelfSort.title => (a, b) => a.title.compareTo(b.title),
    _ShelfSort.category => (a, b) {
      final byCategory = a.category.compareTo(b.category);
      return byCategory != 0 ? byCategory : a.title.compareTo(b.title);
    },
  };

  void _openAllBooks() => setState(() {
    _scope = _ShelfScope.allBooks;
    _selectedGroupId = null;
  });

  void _openGroup(ShelfGroup group) => setState(() {
    _scope = _ShelfScope.group;
    _selectedGroupId = group.id;
  });

  void _backToCards() => setState(() {
    _scope = _ShelfScope.cards;
    _selectedGroupId = null;
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 650;
      final padding = compact ? 20.0 : 40.0;
      final groups = widget.controller.shelfGroups;
      final selectedGroup = groups
          .where((group) => group.id == _selectedGroupId)
          .firstOrNull;
      // The selected group can disappear while another sheet is open.
      final scope = _scope == _ShelfScope.group && selectedGroup == null
          ? _ShelfScope.cards
          : _scope;
      final query = _query.trim().toLowerCase();
      final searching = query.isNotEmpty;
      // Searching always shows books, never group cards: the result of a query
      // is a list of books, and wechat reading behaves the same way.
      final showCards =
          groups.isNotEmpty && scope == _ShelfScope.cards && !searching;
      final allBooks = [...widget.controller.books]..sort(_comparator);
      final scoped = scope == _ShelfScope.group && selectedGroup != null
          ? allBooks.where((book) => selectedGroup.containsBook(book.id))
          : allBooks;
      final books = searching
          ? scoped
                .where(
                  (book) => '${book.title} ${book.author}'
                      .toLowerCase()
                      .contains(query),
                )
                .toList()
          : scoped.toList();
      final recent = widget.controller.recentBook;
      final columns = compact ? 3 : (constraints.maxWidth < 950 ? 3 : 4);
      final gridSpacing = compact ? 18.0 : 28.0;
      final coverWidth = math.min(
        (constraints.maxWidth - padding * 2 - (columns - 1) * gridSpacing) /
            columns,
        compact ? 118.0 : 156.0,
      );
      // Cards are narrower than book covers so a 3-across card row fits the
      // same width as the 3-across book grid it replaces.
      final cardColumns = compact ? 3 : (constraints.maxWidth < 950 ? 4 : 5);
      final cardSpacing = compact ? 13.0 : 20.0;
      final cardWidth =
          (constraints.maxWidth -
              padding * 2 -
              (cardColumns - 1) * cardSpacing) /
          cardColumns;
      return CustomScrollView(
        key: const PageStorageKey('shelf'),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              padding,
              compact ? 14 : 26,
              padding,
              0,
            ),
            sliver: SliverList.list(
              children: [
                _SearchPill(
                  onChanged: (value) => setState(() => _query = value),
                  onDiscover: widget.onDiscover,
                ),
                const SizedBox(height: 8),
                if (scope == _ShelfScope.cards)
                  _titleRow()
                else
                  _groupRow(
                    scope == _ShelfScope.allBooks
                        ? '全部书籍'
                        : selectedGroup!.name,
                    books.length,
                  ),
                const SizedBox(height: 2),
                _sortRow(),
                const SizedBox(height: 12),
                if (!showCards &&
                    !searching &&
                    recent != null &&
                    _sort == _ShelfSort.recent) ...[
                  _ContinueReading(
                    book: recent,
                    controller: widget.controller,
                    compact: compact,
                    onOpen: () => widget.onOpen(recent),
                  ),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
          if (showCards)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cardColumns,
                  crossAxisSpacing: cardSpacing,
                  mainAxisSpacing: 20,
                  mainAxisExtent: cardWidth * 268 / 205 + 50,
                ),
                itemCount: groups.length + 2,
                itemBuilder: (context, index) {
                  if (index == groups.length + 1) {
                    return _NewGroupCard(
                      key: const Key('shelf-group-new-card'),
                      onTap: _manageGroups,
                    );
                  }
                  if (index == 0) {
                    return _GroupCard(
                      key: const Key('shelf-group-all'),
                      title: '全部书籍',
                      books: allBooks.take(4).toList(),
                      total: allBooks.length,
                      reading: allBooks
                          .where((book) => book.hasStarted && !book.finished)
                          .length,
                      controller: widget.controller,
                      onTap: _openAllBooks,
                    );
                  }
                  final group = groups[index - 1];
                  final members = allBooks
                      .where((book) => group.containsBook(book.id))
                      .toList();
                  return _GroupCard(
                    key: Key('shelf-group-${group.id}'),
                    title: group.name,
                    books: members.take(4).toList(),
                    total: members.length,
                    reading: members
                        .where((book) => book.hasStarted && !book.finished)
                        .length,
                    controller: widget.controller,
                    onTap: () => _openGroup(group),
                  );
                },
              ),
            )
          else if (books.isEmpty)
            SliverPadding(
              padding: EdgeInsets.all(padding),
              sliver: SliverToBoxAdapter(
                child: EmptyState(
                  title: searching
                      ? '没有找到这本书'
                      : scope == _ShelfScope.group
                      ? '分组里还没有书'
                      : '给好书留个位置',
                  description: searching
                      ? '换一个书名或作者试试。'
                      : scope == _ShelfScope.group
                      ? '从书籍的更多操作中选择“加入分组”。'
                      : '从公版书库挑一本，或导入自己的 TXT。',
                  action: searching
                      ? null
                      : scope == _ShelfScope.group
                      ? OutlinedButton(
                          onPressed: _backToCards,
                          child: const Text('返回分组'),
                        )
                      : OutlinedButton(
                          onPressed: widget.onDiscover,
                          child: const Text('去发现好书'),
                        ),
                ),
              ),
            )
          else if (_list)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              sliver: SliverList.separated(
                itemCount: books.length,
                separatorBuilder: (_, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final book = books[index];
                  return QuietPanel(
                    padding: const EdgeInsets.all(16),
                    child: InkWell(
                      key: Key('book-${book.id}'),
                      onTap: () => widget.onOpen(book),
                      child: Row(
                        children: [
                          BookCover(
                            book: book,
                            imageLoader: widget.controller.loadBookCover,
                            width: 56,
                            height: 78,
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  book.title,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${book.author} · ${book.progressLabel}',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _menu(book),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: gridSpacing,
                  mainAxisSpacing: 24,
                  mainAxisExtent: coverWidth * 1.4 + 102,
                ),
                itemCount: books.length,
                itemBuilder: (context, index) =>
                    _bookTile(books[index], coverWidth),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(padding, 0, padding, 32),
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    size: 16,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '书与阅读记录，安心留在本机。',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ),
                  if (!compact)
                    TextButton(
                      onPressed: widget.onDiscover,
                      child: const Text('发现下一本  →'),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _titleRow() => Row(
    children: [
      const Expanded(
        child: Text(
          '书架',
          key: Key('shelf-title'),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -.3,
          ),
        ),
      ),
      IconButton(
        key: const Key('shelf-group-manage'),
        tooltip: '管理分组',
        onPressed: _manageGroups,
        icon: const Icon(Icons.tune, size: 20),
      ),
      const SizedBox(width: 4),
      Tooltip(
        message: '批量导入 TXT 或 EPUB',
        child: FilledButton.icon(
          key: const Key('import-book'),
          onPressed: widget.onImport,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          icon: const Icon(Icons.add, size: 17),
          label: const Text('导入'),
        ),
      ),
    ],
  );

  Widget _groupRow(String title, int count) => Row(
    children: [
      IconButton(
        key: const Key('shelf-scope-back'),
        tooltip: '返回分组',
        onPressed: _backToCards,
        icon: const Icon(Icons.arrow_back_ios_new, size: 17),
      ),
      const SizedBox(width: 2),
      Flexible(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            letterSpacing: -.2,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Text(
        '$count 本',
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
      const Spacer(),
      IconButton(
        key: const Key('shelf-group-manage'),
        tooltip: '管理分组',
        onPressed: _manageGroups,
        icon: const Icon(Icons.tune, size: 20),
      ),
    ],
  );

  Widget _sortRow() => Row(
    children: [
      for (final (sort, label) in const [
        (_ShelfSort.recent, '默认'),
        (_ShelfSort.progress, '进度'),
        (_ShelfSort.title, '书名'),
        (_ShelfSort.category, '分类'),
      ])
        Padding(
          padding: const EdgeInsets.only(right: 18),
          child: InkWell(
            key: Key('shelf-sort-${sort.name}'),
            onTap: () => setState(() => _sort = sort),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: _sort == sort ? AppColors.blue : AppColors.muted,
                  fontWeight: _sort == sort ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      const Spacer(),
      IconButton(
        tooltip: _list ? '网格视图' : '列表视图',
        onPressed: () => setState(() => _list = !_list),
        icon: Icon(
          _list ? Icons.grid_view_rounded : Icons.view_list_outlined,
          size: 21,
        ),
      ),
    ],
  );

  Widget _bookTile(Book book, double coverWidth) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InkWell(
        key: Key('book-${book.id}'),
        onTap: () => widget.onOpen(book),
        borderRadius: BorderRadius.circular(5),
        child: BookCover(
          book: book,
          imageLoader: widget.controller.loadBookCover,
          width: coverWidth,
          height: coverWidth * 1.4,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        book.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Text(
        book.author,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
      Row(
        children: [
          Expanded(
            child: Text(
              book.progressLabel,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ),
          SizedBox(width: 32, height: 32, child: _menu(book)),
        ],
      ),
    ],
  );

  Widget _menu(Book book) => PopupMenuButton<String>(
    tooltip: '${book.title}的更多操作',
    padding: EdgeInsets.zero,
    iconSize: 19,
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'details', child: Text('书籍信息')),
      const PopupMenuItem(value: 'groups', child: Text('加入分组')),
      const PopupMenuItem(value: 'remove', child: Text('移出书架')),
    ],
    onSelected: (value) async {
      if (value == 'details') {
        widget.onDetails(book);
        return;
      }
      if (value == 'groups') {
        _editBookGroups(book);
        return;
      }
      if (!await confirmRemoval(
        context,
        '移除《${book.title}》？',
        '将删除这本书的本地正文、阅读进度和笔记。原始 TXT 文件不会被删除。',
      )) {
        return;
      }
      try {
        await widget.controller.removeBook(book.id);
      } catch (error) {
        if (mounted) showMessage(context, errorMessage(error));
      }
    },
  );
}

/// The wechat-reading style search pill: one rounded field with a 书城 action
/// on its right that leads to the discover page.
class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onChanged, required this.onDiscover});
  final ValueChanged<String> onChanged;
  final VoidCallback onDiscover;
  @override
  Widget build(BuildContext context) => Container(
    height: 38,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        const SizedBox(width: 14),
        const Icon(Icons.search, size: 19, color: AppColors.muted),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            key: const Key('shelf-search'),
            onChanged: onChanged,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(fontSize: 13.5),
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              hintText: '搜索书名或作者',
              hintStyle: TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
          ),
        ),
        Container(width: 1, height: 16, color: AppColors.line),
        TextButton(
          key: const Key('shelf-discover'),
          onPressed: onDiscover,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            foregroundColor: AppColors.ink,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('书城'),
        ),
      ],
    ),
  );
}

/// One group card: the first four covers of the group as a 2x2 collage.
///
/// The collage keeps a fixed 205:268 aspect ratio whatever the book count, so
/// a group with one book shows one cover and blank space instead of stretching
/// that cover across the card — this is what wechat reading does.
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    super.key,
    required this.title,
    required this.books,
    required this.total,
    required this.reading,
    required this.controller,
    required this.onTap,
  });
  final String title;
  final List<Book> books;
  final int total;
  final int reading;
  final AppController controller;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 205 / 268,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: _Collage(
                  books: books,
                  controller: controller,
                  emptyLabel: title,
                ),
              ),
              if (reading > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF04438),
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(5),
                        bottomLeft: Radius.circular(5),
                      ),
                    ),
                    child: Text(
                      '在读 $reading',
                      key: Key('shelf-group-reading-$title'),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2B3038),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$total 本',
          style: const TextStyle(fontSize: 10, color: Color(0xFF9AA1AD)),
        ),
      ],
    ),
  );
}

class _Collage extends StatelessWidget {
  const _Collage({
    required this.books,
    required this.controller,
    required this.emptyLabel,
  });
  final List<Book> books;
  final AppController controller;
  final String emptyLabel;
  static const _gap = 2.0;
  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return ColoredBox(
        color: const Color(0xFFF1F2F4),
        child: Center(
          child: Text(
            emptyLabel,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFF9AA1AD)),
          ),
        ),
      );
    }
    if (books.length == 1) return _slot(0);
    // Two books split the card left/right; three or four use a 2x2 grid with
    // the missing slot left blank.
    final rows = books.length == 2 ? 1 : 2;
    return Column(
      children: [
        for (var row = 0; row < rows; row++) ...[
          if (row > 0) const SizedBox(height: _gap),
          Expanded(
            child: Row(
              children: [
                for (var column = 0; column < 2; column++) ...[
                  if (column > 0) const SizedBox(width: _gap),
                  Expanded(child: _slot(row * 2 + column)),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// [BookCover] takes explicit sizes, so every slot measures the box it was
  /// given instead of stretching — an infinite size would break its painted
  /// fallback.
  Widget _slot(int index) => LayoutBuilder(
    builder: (context, constraints) {
      if (index >= books.length) {
        return const ColoredBox(color: Color(0xFFF4F5F7));
      }
      return BookCover(
        book: books[index],
        imageLoader: controller.loadBookCover,
        width: constraints.maxWidth,
        height: constraints.maxHeight,
      );
    },
  );
}

class _NewGroupCard extends StatelessWidget {
  const _NewGroupCard({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 205 / 268,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.line),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 22, color: Color(0xFFB6BCC7)),
                  SizedBox(height: 6),
                  Text(
                    '新建分组',
                    style: TextStyle(fontSize: 10, color: Color(0xFF9AA1AD)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          ' ',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        const Text(' ', style: TextStyle(fontSize: 10)),
      ],
    ),
  );
}

class _ContinueReading extends StatelessWidget {
  const _ContinueReading({
    required this.book,
    required this.controller,
    required this.compact,
    required this.onOpen,
  });
  final Book book;
  final AppController controller;
  final bool compact;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => QuietPanel(
    padding: EdgeInsets.all(compact ? 16 : 24),
    child: Row(
      children: [
        BookCover(
          book: book,
          imageLoader: controller.loadBookCover,
          width: compact ? 62 : 84,
          height: compact ? 88 : 118,
        ),
        SizedBox(width: compact ? 16 : 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.hasStarted ? '接着上次，继续读' : '从这里，翻开新的一页',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                book.hasStarted
                    ? '${book.author} · ${book.progressLabel}'
                    : '${book.author} · 公版节选',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                ),
                child: Text(book.hasStarted ? '继续阅读  →' : '开始阅读  →'),
              ),
            ],
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 32),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '读书，是另一种抵达。',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    book.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.9,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
