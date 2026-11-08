import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../domain/shelf_group.dart';
import '../components/book_cover.dart';
import '../components/common.dart';
import '../components/design.dart';
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

/// The status filter the draft puts on the shelf's filter line.
///
/// It replaces the old 全部/在读/已读 chips: the chip row is gone, but the
/// same three states stay reachable from one dropdown above the grid.
enum _ShelfStatus {
  all('全部状态'),
  reading('在读'),
  finished('已读'),
  unread('未读');

  const _ShelfStatus(this.label);
  final String label;

  bool matches(Book book) => switch (this) {
    _ShelfStatus.all => true,
    _ShelfStatus.reading => book.hasStarted && !book.finished,
    _ShelfStatus.finished => book.finished,
    _ShelfStatus.unread => !book.hasStarted,
  };
}

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onDetails,
    required this.onImport,
    required this.onDiscover,
    required this.onSearch,
  });
  final AppController controller;
  final ValueChanged<Book> onOpen;
  final ValueChanged<Book> onDetails;
  final VoidCallback onImport;
  final VoidCallback onDiscover;
  final VoidCallback onSearch;
  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
  String _query = '';
  _ShelfSort _sort = _ShelfSort.recent;
  _ShelfScope _scope = _ShelfScope.cards;
  String? _selectedGroupId;
  bool _list = false;
  _ShelfStatus _status = _ShelfStatus.all;

  /// Selection mode is 整理书架: the grid becomes checkable and a batch bar
  /// offers 移出书架 / 分组到, mirroring the draft's `shelfOrganize` screen
  /// without leaving the shelf.
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  static final _epoch = DateTime(1970);

  void _enterSelection([String? bookId]) => setState(() {
    _selecting = true;
    if (bookId != null) _selected.add(bookId);
  });

  void _exitSelection() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  void _toggleSelected(String bookId) => setState(() {
    if (!_selected.remove(bookId)) _selected.add(bookId);
  });

  void _openAddSheet() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.background,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('shelf-add-import'),
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('导入书籍'),
            subtitle: const Text('TXT 或 EPUB'),
            onTap: () {
              Navigator.pop(sheetContext);
              widget.onImport();
            },
          ),
          ListTile(
            key: const Key('shelf-add-search'),
            leading: const Icon(Icons.search),
            title: const Text('搜索书籍'),
            subtitle: const Text('在已启用的书源中查找'),
            onTap: () {
              Navigator.pop(sheetContext);
              widget.onSearch();
            },
          ),
          ListTile(
            key: const Key('shelf-add-groups'),
            leading: const Icon(Icons.folder_outlined),
            title: const Text('管理分组'),
            onTap: () {
              Navigator.pop(sheetContext);
              _manageGroups();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  /// Asks which group the selected books join.
  Future<void> _groupSelected() async {
    final groups = widget.controller.shelfGroups;
    if (groups.isEmpty) {
      await _manageGroups();
      return;
    }
    final target = await showModalBottomSheet<ShelfGroup>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.background,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '分组到',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            for (final group in groups)
              ListTile(
                key: Key('shelf-group-target-${group.id}'),
                leading: const Icon(Icons.folder_outlined),
                title: Text(group.name),
                subtitle: Text('${group.bookIds.length} 本'),
                onTap: () => Navigator.pop(sheetContext, group),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    try {
      for (final bookId in _selected) {
        await widget.controller.setShelfGroupMembership(
          target.id,
          bookId,
          true,
        );
      }
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
      return;
    }
    if (!mounted) return;
    showMessage(context, '已加入「${target.name}」。');
    _exitSelection();
  }

  Future<void> _removeSelected() async {
    final count = _selected.length;
    if (!await confirmRemoval(
      context,
      '把 $count 本书移出书架？',
      '将删除这些书的本地正文、阅读进度和笔记。原始文件不会被删除。',
    )) {
      return;
    }
    try {
      for (final bookId in _selected.toList()) {
        await widget.controller.removeBook(bookId);
      }
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
      return;
    }
    if (mounted) _exitSelection();
  }

  /// Lets a group's card add books that are already on the shelf.
  Future<void> _addBooksToGroup(ShelfGroup group) async {
    final members = widget.controller.books
        .where((book) => !group.containsBook(book.id))
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.background,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .7,
          ),
          child: members.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('书架上的书都已在这个分组里。'),
                )
              : ListView(
                  key: const Key('shelf-group-book-picker'),
                  shrinkWrap: true,
                  children: [
                    for (final book in members)
                      ListTile(
                        key: Key('shelf-group-pick-${book.id}'),
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text(book.title),
                        subtitle: Text(book.author),
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          try {
                            await widget.controller.setShelfGroupMembership(
                              group.id,
                              book.id,
                              true,
                            );
                          } catch (error) {
                            if (mounted) {
                              showMessage(context, errorMessage(error));
                            }
                          }
                        },
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  void _openStatusFilter() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.background,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final status in _ShelfStatus.values)
            ListTile(
              key: Key('shelf-status-${status.name}'),
              title: Text(status.label),
              trailing: status == _status
                  ? const Icon(Icons.check, size: 20, color: AppColors.blue)
                  : null,
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => _status = status);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  Future<void> _manageGroups() => showModalBottomSheet<void>(
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
      // The draft's root shelf shows group folders and the books that belong
      // to no group side by side; grouped books only live inside their folder.
      final showCards =
          groups.isNotEmpty && scope == _ShelfScope.cards && !searching;
      final allBooks = [...widget.controller.books]..sort(_comparator);
      final scoped = scope == _ShelfScope.group && selectedGroup != null
          ? allBooks.where((book) => selectedGroup.containsBook(book.id))
          : allBooks;
      final searched = searching
          ? scoped
                .where(
                  (book) => '${book.title} ${book.author}'
                      .toLowerCase()
                      .contains(query),
                )
                .toList()
          : scoped.toList();
      // The status filter narrows what the shelf shows; the count on the filter
      // line and the batch actions all read this same list, so the shelf never
      // offers to act on a book it is not showing.
      final filtered = _status == _ShelfStatus.all
          ? searched
          : searched.where(_status.matches).toList();
      final groupedIds = <String>{for (final group in groups) ...group.bookIds};
      final visible = showCards
          ? filtered.where((book) => !groupedIds.contains(book.id)).toList()
          : filtered;
      // The draft only offers the trailing 添加书籍 card on an unfiltered,
      // unsearched shelf: it stands for the blank space after the last book.
      final addCard = !searching && _status == _ShelfStatus.all;
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

      return Column(
        children: [
          Expanded(
            child: CustomScrollView(
              // One offset per scope: opening a group starts at its top,
              // while coming back to the shelf keeps where the reader was.
              key: PageStorageKey(
                'shelf-${_scope.name}-${_selectedGroupId ?? ''}',
              ),
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
                      ),
                      const SizedBox(height: 10),
                      if (_selecting)
                        _selectionRow(visible)
                      else if (scope == _ShelfScope.cards)
                        _titleRow()
                      else
                        _groupRow(
                          scope == _ShelfScope.allBooks
                              ? '全部书籍'
                              : selectedGroup!.name,
                          visible.length,
                        ),
                      if (!_selecting) ...[
                        const SizedBox(height: 10),
                        _filterRow(filtered.length),
                        const SizedBox(height: 2),
                        _sortRow(),
                      ],
                      const SizedBox(height: 12),
                      if (!showCards &&
                          !searching &&
                          !_selecting &&
                          recent != null &&
                          _sort == _ShelfSort.recent &&
                          _status == _ShelfStatus.all) ...[
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
                if (showCards) ...[
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
                                .where(
                                  (book) => book.hasStarted && !book.finished,
                                )
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
                              .where(
                                (book) => book.hasStarted && !book.finished,
                              )
                              .length,
                          controller: widget.controller,
                          onTap: () => _openGroup(group),
                          onLongPress: _manageGroups,
                        );
                      },
                    ),
                  ),
                  if (visible.isNotEmpty || addCard) ...[
                    const SliverToBoxAdapter(child: SizedBox(height: 22)),
                    _bookGrid(
                      visible,
                      coverWidth,
                      padding,
                      withAddCard: addCard,
                      columns: columns,
                      gridSpacing: gridSpacing,
                    ),
                  ],
                ] else if (visible.isEmpty)
                  SliverPadding(
                    padding: EdgeInsets.all(padding),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          EmptyState(
                            title: searching
                                ? '没有找到这本书'
                                : _status != _ShelfStatus.all
                                ? '暂时没有${_status.label}的书'
                                : scope == _ShelfScope.group
                                ? '分组里还没有书'
                                : '给好书留个位置',
                            description: searching
                                ? '换一个书名或作者试试。'
                                : _status != _ShelfStatus.all
                                ? '试试其他阅读状态。'
                                : scope == _ShelfScope.group
                                ? '从书籍的更多操作中选择“加入分组”。'
                                : '从公版书库挑一本，或导入自己的 TXT。',
                            action: searching
                                ? null
                                : _status != _ShelfStatus.all
                                ? OutlinedButton(
                                    onPressed: () => setState(
                                      () => _status = _ShelfStatus.all,
                                    ),
                                    child: const Text('查看全部状态'),
                                  )
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
                          // An empty group keeps its folder: the draft adds books
                          // from inside it rather than sending the reader back.
                          if (scope == _ShelfScope.group && !searching) ...[
                            const SizedBox(height: 22),
                            SizedBox(
                              width: coverWidth,
                              child: _AddBookCard(
                                key: const Key('shelf-group-add-books'),
                                width: coverWidth,
                                label: '从书架选择',
                                onTap: () => _addBooksToGroup(selectedGroup!),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else if (_list)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) => _bookRow(visible[index]),
                    ),
                  )
                else
                  _bookGrid(
                    visible,
                    coverWidth,
                    padding,
                    withAddCard: addCard,
                    columns: columns,
                    gridSpacing: gridSpacing,
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      _selecting ? 24 : 26,
                      padding,
                      12,
                    ),
                    child: Text(
                      _footerNote(showCards),
                      key: const Key('shelf-foot'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_selecting) _batchBar(),
        ],
      );
    },
  );

  /// The draft's footer: hints at the long press that starts 整理书架, and names
  /// the group while drilled into one.
  String _footerNote(bool showCards) {
    if (_scope == _ShelfScope.group) {
      final group = widget.controller.shelfGroups
          .where((group) => group.id == _selectedGroupId)
          .firstOrNull;
      return '${widget.controller.books.where((book) => group?.containsBook(book.id) ?? false).length} 本书 · ${group?.name ?? ''}';
    }
    if (showCards) return '长按书籍或分组，即可整理书架';
    return '每一本书，都有自己的位置';
  }

  /// The book grid plus the draft's trailing 添加书籍 card.
  Widget _bookGrid(
    List<Book> books,
    double coverWidth,
    double padding, {
    required bool withAddCard,
    required int columns,
    required double gridSpacing,
  }) => SliverPadding(
    padding: EdgeInsets.symmetric(horizontal: padding),
    sliver: SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: gridSpacing,
        mainAxisSpacing: 24,
        mainAxisExtent: coverWidth * 1.4 + 102,
      ),
      itemCount: books.length + (withAddCard ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= books.length) {
          final inGroup = _scope == _ShelfScope.group;
          return _AddBookCard(
            key: Key(inGroup ? 'shelf-group-add-books' : 'shelf-add-card'),
            width: coverWidth,
            label: inGroup ? '从书架选择' : '导入 · 搜索',
            onTap: inGroup
                ? () => _addBooksToGroup(
                    widget.controller.shelfGroups.firstWhere(
                      (group) => group.id == _selectedGroupId,
                    ),
                  )
                : _openAddSheet,
          );
        }
        return _bookTile(books[index], coverWidth);
      },
    ),
  );

  Widget _bookRow(Book book) => QuietPanel(
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
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  '${book.author} · ${book.progressLabel}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          _menu(book),
        ],
      ),
    ),
  );

  /// 整理书架's header row: the draft swaps the title for the selection count
  /// and offers 全选 / 完成 in place of the filter line.
  Widget _selectionRow(List<Book> visible) {
    final all =
        visible.isNotEmpty &&
        visible.every((book) => _selected.contains(book.id));
    return Row(
      children: [
        Expanded(
          child: Text(
            _selected.isEmpty ? '整理书架' : '已选 ${_selected.length} 本',
            key: const Key('shelf-selection-title'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -.3,
            ),
          ),
        ),
        TextButton(
          key: const Key('shelf-select-all'),
          onPressed: visible.isEmpty
              ? null
              : () => setState(() {
                  if (all) {
                    _selected.clear();
                  } else {
                    _selected.addAll(visible.map((book) => book.id));
                  }
                }),
          child: Text(all ? '取消全选' : '全选'),
        ),
        TextButton(
          key: const Key('shelf-select-done'),
          onPressed: _exitSelection,
          child: const Text('完成'),
        ),
      ],
    );
  }

  /// The draft's filter line: a status dropdown, the visible count, and the
  /// entry point into 整理书架.
  Widget _filterRow(int count) => Row(
    children: [
      InkWell(
        key: const Key('shelf-status-filter'),
        onTap: _openStatusFilter,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Row(
            children: [
              Text(
                _status.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.expand_more, size: 17, color: AppColors.muted),
            ],
          ),
        ),
      ),
      const Spacer(),
      Text(
        '$count 本书',
        key: const Key('shelf-count'),
        style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
      ),
      const SizedBox(width: 10),
      TextButton(
        key: const Key('shelf-select'),
        onPressed: count == 0 ? null : () => _enterSelection(),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: const Text('选择'),
      ),
    ],
  );

  /// The draft's sticky batch bar: 移出书架 / 分组到, disabled until a book is
  /// picked.
  Widget _batchBar() => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
    child: SafeArea(
      top: false,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('shelf-batch-remove'),
              onPressed: _selected.isEmpty ? null : _removeSelected,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                textStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('移出书架'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              key: const Key('shelf-batch-group'),
              onPressed: _selected.isEmpty ? null : _groupSelected,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                textStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              icon: const Icon(Icons.folder_outlined, size: 18),
              label: Text(
                _selected.isEmpty ? '分组到' : '分组到 · ${_selected.length}',
              ),
            ),
          ),
        ],
      ),
    ),
  );

  /// The draft's shelf header: a large title with search and add actions.
  ///
  /// 管理分组 lost its own button here — the draft puts it behind the add
  /// sheet, and the group row keeps its own entry for the drilled-in layer.
  Widget _titleRow() => Row(
    key: const Key('shelf-title-row'),
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: const Text(
            '书架',
            key: Key('shelf-title'),
            style: TextStyle(
              fontSize: 28,
              height: 1.25,
              fontWeight: FontWeight.w700,
              letterSpacing: -.4,
              color: AppColors.ink,
            ),
          ),
        ),
      ),
      CircleIconButton(
        key: const Key('shelf-search-action'),
        icon: Icons.search,
        tooltip: '搜索书籍',
        onPressed: widget.onSearch,
      ),
      const SizedBox(width: 8),
      CircleIconButton(
        key: const Key('shelf-add'),
        icon: Icons.add,
        tooltip: '添加书籍',
        onPressed: _openAddSheet,
      ),
    ],
  );

  /// The drilled-in layer's header: back, group name, count, and the group's
  /// own 更多 menu (the draft's shelf-group-menu).
  Widget _groupRow(String title, int count) => Row(
    key: const Key('shelf-group-row'),
    children: [
      CircleIconButton(
        key: const Key('shelf-scope-back'),
        icon: Icons.chevron_left,
        tooltip: '返回分组',
        onPressed: _backToCards,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            letterSpacing: -.2,
            color: AppColors.ink,
          ),
        ),
      ),
      Text(
        '$count 本',
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
      const SizedBox(width: 6),
      IconButton(
        key: const Key('shelf-group-manage'),
        tooltip: '管理分组',
        onPressed: _manageGroups,
        icon: const Icon(Icons.more_horiz, size: 20),
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

  /// One book on the grid.
  ///
  /// Outside 整理书架 a long press picks this book and opens selection mode,
  /// exactly like the draft's 550 ms long press. Inside it the cover gains an
  /// outline and a check mark, and a tap toggles instead of opening.
  Widget _bookTile(Book book, double coverWidth) {
    final selected = _selected.contains(book.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onLongPress: _selecting ? null : () => _enterSelection(book.id),
          child: InkWell(
            key: Key('book-${book.id}'),
            onTap: _selecting
                ? () => _toggleSelected(book.id)
                : () => widget.onOpen(book),
            borderRadius: BorderRadius.circular(5),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: _selecting && selected
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.blue, width: 2),
                        )
                      : null,
                  child: BookCover(
                    book: book,
                    imageLoader: widget.controller.loadBookCover,
                    width: coverWidth,
                    height: coverWidth * 1.4,
                  ),
                ),
                if (_selecting)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: _SelectionDot(
                      key: Key('shelf-select-${book.id}'),
                      selected: selected,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          book.author,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        if (_selecting)
          const SizedBox(height: 2)
        else
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
  }

  Widget _menu(Book book) => PopupMenuButton<String>(
    tooltip: '${book.title}的更多操作',
    padding: EdgeInsets.zero,
    iconSize: 19,
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'details', child: Text('书籍信息')),
      const PopupMenuItem(value: 'groups', child: Text('加入分组')),
      // Inside a group the book has to be reachable from the default shelf
      // again; removing it from the shelf would delete the book itself.
      if (_scope == _ShelfScope.group && _selectedGroupId != null)
        const PopupMenuItem(value: 'leave', child: Text('移出分组')),
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
      if (value == 'leave') {
        final groupId = _selectedGroupId;
        if (groupId == null) return;
        try {
          await widget.controller.setShelfGroupMembership(
            groupId,
            book.id,
            false,
          );
        } catch (error) {
          if (mounted) showMessage(context, errorMessage(error));
        }
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

/// The wechat-reading style search pill: one rounded field that fills the row.
class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onChanged});
  final ValueChanged<String> onChanged;
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
            // isDense + zero padding keeps the hint centred in the 38px pill.
            // isCollapsed squeezed the field to 20px and left the hint 6.5px
            // above the centre, and the theme's vertical padding would add
            // another 14px on each side.
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              hintText: '搜索书名或作者',
              hintStyle: TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
          ),
        ),
        const SizedBox(width: 14),
      ],
    ),
  );
}

/// One group card: the first four covers of the group as a 2x2 collage.
///
/// The collage keeps a fixed 205:268 aspect ratio whatever the book count, so
/// a group with one book shows one cover and blank space instead of stretching
/// that cover across the card — this is what wechat reading does.
/// The trailing tile of a book grid: 添加书籍 in the draft's dashed cover style.
///
/// Its caption mirrors a book tile's title line so the tile lines up with the
/// real covers next to it.
class _AddBookCard extends StatelessWidget {
  const _AddBookCard({
    super.key,
    required this.width,
    required this.label,
    required this.onTap,
  });

  final double width;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: width,
          height: width * 1.4,
          child: CustomPaint(
            painter: _DashedBorderPainter(color: AppColors.line),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, size: 30, color: Color(0xFFB6BCC7)),
                  const SizedBox(height: 6),
                  Text(
                    '添加书籍',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
        ),
      ),
    ],
  );
}

/// Dashed 1 px rounded rectangle — Flutter has no dashed border, so the tile
/// paints its own outline instead of faking one with gaps in a solid border.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 6), paint);
        distance += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The check mark a book shows while 整理书架 is open.
class _SelectionDot extends StatelessWidget {
  const _SelectionDot({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? AppColors.blue : Colors.white,
      border: Border.all(
        color: selected ? AppColors.blue : AppColors.line,
        width: 1.5,
      ),
    ),
    child: selected
        ? const Icon(Icons.check, size: 13, color: Colors.white)
        : null,
  );
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    super.key,
    required this.title,
    required this.books,
    required this.total,
    required this.reading,
    required this.controller,
    required this.onTap,
    this.onLongPress,
  });
  final String title;
  final List<Book> books;
  final int total;
  final int reading;
  final AppController controller;
  final VoidCallback onTap;

  /// The draft opens the group's own menu on a long press: rename, add books,
  /// or dissolve the group without drilling in first.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: onLongPress,
    child: InkWell(
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
