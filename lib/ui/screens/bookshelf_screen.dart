import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../components/book_cover.dart';
import '../components/common.dart';
import '../components/shelf_group_sheets.dart';
import '../theme.dart';

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
  int _filter = 0;
  String _sort = '最近阅读';
  String? _selectedGroupId;
  bool _list = false;

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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 650;
      final padding = compact ? 20.0 : 40.0;
      final selectedGroup = widget.controller.shelfGroups
          .where((group) => group.id == _selectedGroupId)
          .firstOrNull;
      final books =
          widget.controller.books.where((book) {
            final matches = '${book.title} ${book.author}'
                .toLowerCase()
                .contains(_query.toLowerCase());
            return matches &&
                (selectedGroup == null ||
                    selectedGroup.containsBook(book.id)) &&
                (_filter == 0 ||
                    (_filter == 1
                        ? book.hasStarted && !book.finished
                        : book.finished));
          }).toList()..sort(
            (a, b) => switch (_sort) {
              '书名' => a.title.compareTo(b.title),
              '加入时间' => b.addedAt.compareTo(a.addedAt),
              _ => (b.lastOpenedAt ?? DateTime(1970)).compareTo(
                a.lastOpenedAt ?? DateTime(1970),
              ),
            },
          );
      final recent = widget.controller.recentBook;
      final columns = compact ? 3 : (constraints.maxWidth < 950 ? 3 : 4);
      final cellWidth =
          (constraints.maxWidth -
              padding * 2 -
              (columns - 1) * (compact ? 18 : 28)) /
          columns;
      final coverWidth = math.min(cellWidth, compact ? 118.0 : 156.0);
      return CustomScrollView(
        key: const PageStorageKey('shelf'),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              padding,
              compact ? 20 : 38,
              padding,
              0,
            ),
            sliver: SliverList.list(
              children: [
                PageHeading(
                  title: '我的书架',
                  subtitle: '把时间，留给好书。',
                  action: compact
                      ? IconButton.filled(
                          key: const Key('import-book'),
                          onPressed: widget.onImport,
                          tooltip: '批量导入 TXT 或 EPUB',
                          icon: const Icon(Icons.add),
                        )
                      : FilledButton.icon(
                          key: const Key('import-book'),
                          onPressed: widget.onImport,
                          icon: const Icon(Icons.add, size: 19),
                          label: const Text('批量导入'),
                        ),
                ),
                const SizedBox(height: 28),
                if (recent != null &&
                    selectedGroup == null &&
                    _query.isEmpty &&
                    _filter == 0) ...[
                  _ContinueReading(
                    book: recent,
                    controller: widget.controller,
                    compact: compact,
                    onOpen: () => widget.onOpen(recent),
                  ),
                  const SizedBox(height: 30),
                ],
                TextField(
                  key: const Key('shelf-search'),
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: '搜索书名或作者',
                    prefixIcon: Icon(Icons.search, size: 21),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(['全部', '在读', '已读'][i]),
                          selected: _filter == i,
                          showCheckmark: false,
                          selectedColor: const Color(0xFFE8EBEF),
                          backgroundColor: Colors.transparent,
                          side: BorderSide.none,
                          onSelected: (_) => setState(() => _filter = i),
                          labelStyle: TextStyle(
                            color: _filter == i
                                ? AppColors.ink
                                : AppColors.muted,
                            fontWeight: _filter == i
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    const Spacer(),
                    IconButton(
                      tooltip: _list ? '网格视图' : '列表视图',
                      onPressed: () => setState(() => _list = !_list),
                      icon: Icon(
                        _list
                            ? Icons.grid_view_rounded
                            : Icons.view_list_outlined,
                        size: 21,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text(
                      '书架分组',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      key: const Key('shelf-group-manage'),
                      onPressed: _manageGroups,
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('管理分组'),
                    ),
                  ],
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: const Key('shelf-group-all'),
                          label: const Text('全部书籍'),
                          selected: selectedGroup == null,
                          showCheckmark: false,
                          selectedColor: AppColors.softBlue,
                          onSelected: (_) =>
                              setState(() => _selectedGroupId = null),
                        ),
                      ),
                      for (final group in widget.controller.shelfGroups)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            key: Key('shelf-group-${group.id}'),
                            label: Text(
                              group.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            selected: selectedGroup?.id == group.id,
                            showCheckmark: false,
                            selectedColor: AppColors.softBlue,
                            onSelected: (_) =>
                                setState(() => _selectedGroupId = group.id),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '${books.length} 本书',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    DropdownButton<String>(
                      value: _sort,
                      underline: const SizedBox.shrink(),
                      icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                      style: const TextStyle(
                        fontFamily: 'NotoSansSC',
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                      items: ['最近阅读', '书名', '加入时间']
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _sort = value!),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          if (books.isEmpty)
            SliverPadding(
              padding: EdgeInsets.all(padding),
              sliver: SliverToBoxAdapter(
                child: EmptyState(
                  title: _query.isNotEmpty
                      ? '没有找到这本书'
                      : selectedGroup != null
                      ? '分组里还没有书'
                      : '给好书留个位置',
                  description: _query.isNotEmpty
                      ? '换一个书名或作者试试。'
                      : selectedGroup != null
                      ? '从书籍的更多操作中选择“加入分组”。'
                      : '从公版书库挑一本，或导入自己的 TXT。',
                  action: _query.isNotEmpty
                      ? null
                      : selectedGroup != null
                      ? OutlinedButton(
                          onPressed: () =>
                              setState(() => _selectedGroupId = null),
                          child: const Text('查看全部书籍'),
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
                  crossAxisSpacing: compact ? 18 : 28,
                  mainAxisSpacing: 24,
                  mainAxisExtent: coverWidth * 1.4 + 102,
                ),
                itemCount: books.length,
                itemBuilder: (context, index) {
                  final book = books[index];
                  return Column(
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
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              book.progressLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                          SizedBox(width: 32, height: 32, child: _menu(book)),
                        ],
                      ),
                    ],
                  );
                },
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
    padding: EdgeInsets.all(compact ? 20 : 28),
    child: Row(
      children: [
        BookCover(
          book: book,
          imageLoader: controller.loadBookCover,
          width: compact ? 78 : 104,
          height: compact ? 110 : 146,
        ),
        SizedBox(width: compact ? 20 : 28),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.hasStarted ? '接着上次，继续读' : '从这里，翻开新的一页',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                book.hasStarted
                    ? '${book.author} · ${book.progressLabel}'
                    : '${book.author} · 公版节选',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 11,
                  ),
                ),
                child: Text(book.hasStarted ? '继续阅读  →' : '开始阅读  →'),
              ),
            ],
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 36),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '读书，是另一种抵达。',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
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
