import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../domain/shelf_group.dart';
import '../components/book_cover.dart';
import '../components/common.dart';
import '../components/design.dart';
import '../components/shelf_group_sheets.dart';
import '../design_icons.dart';
import '../theme.dart';

/// Root shelf vs a single opened group folder.
enum _ShelfScope { root, group }

/// The status filter the draft puts on the shelf's filter line.
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
  _ShelfScope _scope = _ShelfScope.root;
  String? _selectedGroupId;
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
            leading: const Icon(DesignIcons.fileUp),
            title: const Text('导入书籍'),
            subtitle: const Text('TXT 或 EPUB'),
            onTap: () {
              Navigator.pop(sheetContext);
              widget.onImport();
            },
          ),
          ListTile(
            key: const Key('shelf-add-search'),
            leading: const Icon(DesignIcons.search),
            title: const Text('搜索书籍'),
            subtitle: const Text('在已启用的书源中查找'),
            onTap: () {
              Navigator.pop(sheetContext);
              widget.onSearch();
            },
          ),
          ListTile(
            key: const Key('shelf-add-groups'),
            leading: const Icon(DesignIcons.folderOpen),
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
                leading: const Icon(DesignIcons.folderOpen),
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
                        leading: const Icon(DesignIcons.bookOpen),
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
                  ? const Icon(
                      DesignIcons.check,
                      size: 20,
                      color: AppColors.blue,
                    )
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

  int _recentComparator(Book a, Book b) =>
      (b.lastOpenedAt ?? _epoch).compareTo(a.lastOpenedAt ?? _epoch);

  void _openGroup(ShelfGroup group) => setState(() {
    _scope = _ShelfScope.group;
    _selectedGroupId = group.id;
  });

  void _backToRoot() => setState(() {
    _scope = _ShelfScope.root;
    _selectedGroupId = null;
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 650;
      final padding = compact ? AppSpacing.page : AppSpacing.pageWide;
      final groups = widget.controller.shelfGroups;
      final selectedGroup = groups
          .where((group) => group.id == _selectedGroupId)
          .firstOrNull;
      // The selected group can disappear while another sheet is open.
      final scope = _scope == _ShelfScope.group && selectedGroup == null
          ? _ShelfScope.root
          : _scope;
      final allBooks = [...widget.controller.books]..sort(_recentComparator);
      final inGroup = scope == _ShelfScope.group && selectedGroup != null;
      final scoped = inGroup
          ? allBooks.where((book) => selectedGroup.containsBook(book.id))
          : allBooks;
      final filtered = _status == _ShelfStatus.all
          ? scoped.toList()
          : scoped.where(_status.matches).toList();
      final groupedIds = <String>{for (final group in groups) ...group.bookIds};
      // Root (not selecting): folders + ungrouped books. Selection / group
      // drill-in: flat book list only.
      final showFolders =
          scope == _ShelfScope.root && !_selecting && groups.isNotEmpty;
      final visibleBooks = showFolders
          ? filtered.where((book) => !groupedIds.contains(book.id)).toList()
          : filtered;
      // Selection on root must include books that already live in folders.
      final selectionBooks = scope == _ShelfScope.root && _selecting
          ? filtered
          : visibleBooks;
      final addCard = !_selecting && _status == _ShelfStatus.all;
      final recent = widget.controller.recentBook;
      final columns = compact ? 3 : (constraints.maxWidth < 950 ? 3 : 4);
      final gridSpacing = compact ? 22.0 : 28.0;
      final coverWidth = math.min(
        (constraints.maxWidth - padding * 2 - (columns - 1) * gridSpacing) /
            columns,
        compact ? 118.0 : 156.0,
      );
      final hasContent = allBooks.isNotEmpty || groups.isNotEmpty;
      final emptyRoot =
          scope == _ShelfScope.root &&
          !hasContent &&
          _status == _ShelfStatus.all;

      return Column(
        children: [
          Expanded(
            child: CustomScrollView(
              key: PageStorageKey(
                'shelf-${scope.name}-${_selectedGroupId ?? ''}',
              ),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    compact ? 12 : 26,
                    compact ? 19 : padding,
                    0,
                  ),
                  sliver: SliverList.list(
                    children: [
                      if (_selecting)
                        _selectionRow(selectionBooks)
                      else if (scope == _ShelfScope.root)
                        _titleRow()
                      else
                        _groupRow(selectedGroup!.name, filtered.length),
                      if (!_selecting) ...[
                        const SizedBox(height: 10),
                        _filterRow(
                          scope == _ShelfScope.root && !_selecting
                              ? filtered.length
                              : filtered.length,
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (scope == _ShelfScope.root &&
                          !_selecting &&
                          recent != null &&
                          _status == _ShelfStatus.all &&
                          hasContent) ...[
                        _ContinueReading(
                          book: recent,
                          controller: widget.controller,
                          compact: compact,
                          onOpen: () => widget.onOpen(recent),
                        ),
                        const SizedBox(height: 23),
                      ],
                    ],
                  ),
                ),
                if (emptyRoot)
                  SliverPadding(
                    padding: EdgeInsets.all(padding),
                    sliver: SliverToBoxAdapter(
                      child: EmptyBlock(
                        icon: DesignIcons.bookOpen,
                        title: '你的故事，从这里开始',
                        description: '把想读的书放进来\n为自己留一点阅读的时间',
                        primaryLabel: '导入一本书',
                        onPrimary: widget.onImport,
                        secondaryLabel: '新建分组',
                        onSecondary: _manageGroups,
                      ),
                    ),
                  )
                else if (visibleBooks.isEmpty &&
                    !showFolders &&
                    (!addCard || inGroup))
                  SliverPadding(
                    padding: EdgeInsets.all(padding),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          EmptyState(
                            title: _status != _ShelfStatus.all
                                ? '暂时没有${_status.label}的书'
                                : scope == _ShelfScope.group
                                ? '这个分组还没有书'
                                : '暂时没有书',
                            description: _status != _ShelfStatus.all
                                ? '试试其他阅读状态。'
                                : scope == _ShelfScope.group
                                ? '把想一起阅读的书，放在这里。'
                                : '从发现页挑一本，或导入自己的 TXT。',
                            action: _status != _ShelfStatus.all
                                ? OutlinedButton(
                                    onPressed: () => setState(
                                      () => _status = _ShelfStatus.all,
                                    ),
                                    child: const Text('查看全部状态'),
                                  )
                                : scope == _ShelfScope.group
                                ? OutlinedButton(
                                    onPressed: () =>
                                        _addBooksToGroup(selectedGroup!),
                                    child: const Text('添加书籍到分组'),
                                  )
                                : OutlinedButton(
                                    onPressed: widget.onDiscover,
                                    child: const Text('去发现好书'),
                                  ),
                          ),
                          if (scope == _ShelfScope.group) ...[
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
                else
                  _mixedGrid(
                    groups: showFolders ? groups : const [],
                    books: _selecting ? selectionBooks : visibleBooks,
                    coverWidth: coverWidth,
                    padding: padding,
                    withAddCard: addCard,
                    columns: columns,
                    gridSpacing: gridSpacing,
                    allBooks: allBooks,
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
                      _footerNote(scope, showFolders),
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

  String _footerNote(_ShelfScope scope, bool showFolders) {
    if (scope == _ShelfScope.group) {
      final group = widget.controller.shelfGroups
          .where((group) => group.id == _selectedGroupId)
          .firstOrNull;
      return '${widget.controller.books.where((book) => group?.containsBook(book.id) ?? false).length} 本书 · ${group?.name ?? ''}';
    }
    return '长按书籍或分组，即可整理书架';
  }

  DateTime _latestOpened(ShelfGroup group, List<Book> books) {
    var latest = _epoch;
    for (final book in books) {
      if (!group.containsBook(book.id)) continue;
      final opened = book.lastOpenedAt ?? _epoch;
      if (opened.isAfter(latest)) latest = opened;
    }
    return latest;
  }

  /// Root grid ordered by the latest read inside each tile.
  ///
  /// A group uses its most recently opened member, so an unread folder does
  /// not stay pinned ahead of a book the reader just opened.
  List<Object> _shelfTiles({
    required List<ShelfGroup> groups,
    required List<Book> books,
    required List<Book> allBooks,
  }) {
    if (groups.isEmpty) return books;
    final tiles =
        <({DateTime readAt, DateTime tie, Object item})>[
          for (final group in groups)
            (
              readAt: _latestOpened(group, allBooks),
              tie: group.createdAt,
              item: group,
            ),
          for (final book in books)
            (
              readAt: book.lastOpenedAt ?? _epoch,
              tie: book.addedAt,
              item: book,
            ),
        ]..sort((a, b) {
          final byRead = b.readAt.compareTo(a.readAt);
          return byRead != 0 ? byRead : b.tie.compareTo(a.tie);
        });
    return [for (final tile in tiles) tile.item];
  }

  /// Draft root grid: group folders and ungrouped books, then the add tile.
  Widget _mixedGrid({
    required List<ShelfGroup> groups,
    required List<Book> books,
    required List<Book> allBooks,
    required double coverWidth,
    required double padding,
    required bool withAddCard,
    required int columns,
    required double gridSpacing,
  }) {
    final tiles = _shelfTiles(groups: groups, books: books, allBooks: allBooks);
    final itemCount = tiles.length + (withAddCard ? 1 : 0);
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: gridSpacing,
          mainAxisSpacing: 25,
          mainAxisExtent: coverWidth * 1.4 + 72,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index < tiles.length && tiles[index] is ShelfGroup) {
            final group = tiles[index] as ShelfGroup;
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
              width: coverWidth,
              onTap: () => _openGroup(group),
              onLongPress: _manageGroups,
            );
          }
          if (index < tiles.length) {
            return _bookTile(tiles[index] as Book, coverWidth);
          }
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
        },
      ),
    );
  }

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
              const Icon(
                DesignIcons.chevronDown,
                size: 17,
                color: AppColors.muted,
              ),
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
              icon: const Icon(DesignIcons.trash, size: 18),
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
              icon: const Icon(DesignIcons.folderOpen, size: 18),
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
        icon: DesignIcons.search,
        tooltip: '搜索书籍',
        onPressed: widget.onSearch,
      ),
      const SizedBox(width: 8),
      CircleIconButton(
        key: const Key('shelf-add'),
        icon: DesignIcons.plus,
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
        icon: DesignIcons.chevronLeft,
        tooltip: '返回分组',
        onPressed: _backToRoot,
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
        icon: const Icon(DesignIcons.ellipsis, size: 20),
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
                    onMissingCover: widget.controller.ensureBookCover,
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
        const SizedBox(height: 11),
        Text(
          book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: Text(
                book.progressLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Color(0xFFA2A6AF)),
              ),
            ),
            if (!_selecting)
              SizedBox(width: 28, height: 28, child: _menu(book)),
          ],
        ),
      ],
    );
  }

  Widget _menu(Book book) => PopupMenuButton<String>(
    tooltip: '${book.title}的更多操作',
    padding: EdgeInsets.zero,
    iconSize: 16,
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

/// The trailing tile of a book grid: 添加书籍 in the draft's dashed cover style.
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
            child: const Center(
              child: Icon(DesignIcons.plus, size: 28, color: Color(0xFFB6BCC7)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 11),
      const Text(
        '添加书籍',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.ink,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10, color: Color(0xFFA2A6AF)),
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
        ? const Icon(DesignIcons.check, size: 13, color: Colors.white)
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
    required this.width,
    required this.onTap,
    this.onLongPress,
  });
  final String title;
  final List<Book> books;
  final int total;
  final int reading;
  final AppController controller;
  final double width;
  final VoidCallback onTap;
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
          SizedBox(
            width: width,
            height: width * 1.4,
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
          const SizedBox(height: 12),
          Text(
            title,
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
            '$total 本',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
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
    // A single book fills the cover. Two books sit side by side, and three
    // or four use a 2×2 grid with the empty slot left blank.
    if (books.length <= 1) return _slot(0);
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
        onMissingCover: controller.ensureBookCover,
        width: constraints.maxWidth,
        height: constraints.maxHeight,
      );
    },
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
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 15 : 24,
      vertical: compact ? 16 : 24,
    ),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(compact ? 13 : 16),
    ),
    child: Row(
      children: [
        BookCover(
          book: book,
          imageLoader: controller.loadBookCover,
          onMissingCover: controller.ensureBookCover,
          width: compact ? 47 : 64,
          height: compact ? 68 : 92,
        ),
        SizedBox(width: compact ? 14 : 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.hasStarted ? '接着上次，继续读' : '从这里，翻开新的一页',
                style: const TextStyle(
                  color: Color(0xFF9A9FA9),
                  fontSize: 10,
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(height: 6),
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
              const SizedBox(height: 8),
              Text(
                _statusLine(book),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Color(0xFF999FAA)),
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
                    bookIntroText(book.description),
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
        const SizedBox(width: 8),
        Tooltip(
          message: '继续阅读${book.title}',
          child: Material(
            color: Colors.white,
            elevation: 1,
            shadowColor: const Color(0x14203050),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('shelf-continue'),
              onTap: onOpen,
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 35,
                height: 35,
                child: Icon(DesignIcons.play, size: 17, color: AppColors.blue),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  static String _statusLine(Book book) {
    if (!book.hasStarted || book.chapters.isEmpty) return book.progressLabel;
    final index = book.position.chapterIndex.clamp(0, book.chapters.length - 1);
    return '${book.chapters[index].title} · ${book.progressLabel}';
  }
}
