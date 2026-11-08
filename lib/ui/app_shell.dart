import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../application/app_controller.dart';
import '../domain/book.dart';
import 'components/book_details.dart';
import 'components/brand_mark.dart';
import 'components/common.dart';
import 'screens/app_settings_screen.dart';
import 'screens/backup_screen.dart';
import 'screens/bookshelf_screen.dart';
import 'screens/discover_screen.dart';
import 'screens/import_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/reading_history_screen.dart';
import 'screens/search_screen.dart';
import 'screens/sources_screen.dart';
import 'theme.dart';

typedef LocalBookFilePicker = Future<List<LocalImportFile>?> Function();

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller, this.pickLocalFiles});
  final AppController controller;
  final LocalBookFilePicker? pickLocalFiles;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selected = 0;
  bool _importing = false;
  bool _opening = false;

  // 设计稿固定底部三项；书源管理属于维护型功能，按稿收进「我的」。
  static const _labels = ['书架', '发现', '我的'];
  static const _icons = [
    Icons.auto_stories_outlined,
    Icons.explore_outlined,
    Icons.person_outline,
  ];

  void _select(int index) => setState(() => _selected = index);

  Future<void> _open(Book book, {ReadingPosition? position}) async {
    if (_opening) return;
    _opening = true;
    try {
      final added = await widget.controller.addBook(book);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          settings: RouteSettings(
            name: '/read/${Uri.encodeComponent(added.id)}',
          ),
          builder: (_) => ReaderScreen(
            controller: widget.controller,
            bookId: added.id,
            initialPosition: position,
          ),
        ),
      );
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
    } finally {
      _opening = false;
    }
  }

  void _details(Book book) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) =>
        BookDetails(book: book, controller: widget.controller, onRead: _open),
  );

  Future<List<LocalImportFile>?> _pickLocalFiles() async {
    final picker = widget.pickLocalFiles;
    if (picker != null) return picker();

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'epub'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return null;

    final files = <LocalImportFile>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) {
        throw const FormatException('无法读取文件，请重新选择本地 TXT 或 EPUB。');
      }
      files.add((bytes: bytes, fileName: file.name));
    }
    return files;
  }

  Future<void> _import() async {
    if (_importing) return;
    _importing = true;
    try {
      final files = await _pickLocalFiles();
      if (!mounted || files == null) return;
      final books = await widget.controller.importLocalFiles(files);
      if (mounted) {
        _select(0);
        final message = switch (books.length) {
          0 => '所选书籍已在书架中。',
          1 => '《${books.single.title}》已加入书架。',
          _ => '已导入 ${books.length} 本书。',
        };
        showMessage(context, message);
      }
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
    } finally {
      _importing = false;
    }
  }

  void _push(Widget screen) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));

  void _sources() => _push(SourcesScreen(controller: widget.controller));

  void _importScreen() => _push(
    ImportScreen(
      controller: widget.controller,
      onPickFiles: _import,
      onSources: _sources,
    ),
  );

  void _backup() => _push(BackupScreen(controller: widget.controller));

  void _settings() => _push(
    AppSettingsScreen(
      controller: widget.controller,
      onSources: _sources,
      onBackup: _backup,
    ),
  );

  void _search() => _push(
    SearchScreen(
      controller: widget.controller,
      onDetails: _details,
      onOpen: _open,
    ),
  );

  void _notes() => _push(
    NotesScreen(
      controller: widget.controller,
      onOpen: (note) {
        final book = widget.controller.book(note.bookId);
        if (book == null) return;
        _open(
          book,
          position: ReadingPosition(
            chapterIndex: note.chapterIndex,
            paragraphIndex: note.paragraphIndex,
          ),
        );
      },
    ),
  );

  void _history() => _push(
    ReadingHistoryScreen(
      controller: widget.controller,
      onOpen: (activity) {
        final book = widget.controller.book(activity.bookId);
        if (book == null ||
            book.sourceId != activity.sourceId ||
            activity.chapterIndex < 0 ||
            activity.chapterIndex >= book.chapters.length ||
            book.chapters[activity.chapterIndex].id != activity.chapterId) {
          showMessage(context, '书籍来源或章节已变化，无法打开这条阅读足迹。');
          return;
        }
        _open(
          book,
          position: ReadingPosition(chapterIndex: activity.chapterIndex),
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        final content = IndexedStack(
          index: _selected,
          children: [
            BookshelfScreen(
              controller: widget.controller,
              onOpen: _open,
              onDetails: _details,
              onImport: _importScreen,
              onDiscover: () => _select(1),
              onSearch: _search,
            ),
            DiscoverScreen(
              controller: widget.controller,
              onDetails: _details,
              onOpen: _open,
              onSources: _sources,
              onBack: () => _select(0),
            ),
            ProfileScreen(
              controller: widget.controller,
              onNotes: _notes,
              onHistory: _history,
              onSources: _sources,
              onImport: _importScreen,
              onBackup: _backup,
              onSettings: _settings,
            ),
          ],
        );
        return Scaffold(
          // No global app bar: every screen owns its own header (the shelf has
          // its title row, discover its own toolbar), and a brand bar on top of
          // them only repeated the product name.
          body: SafeArea(
            top: true,
            bottom: false,
            child: Row(
              children: [
                if (wide)
                  SizedBox(
                    width: 224,
                    child: ColoredBox(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 36,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(left: 12),
                              child: Row(
                                children: [
                                  BrandMark(),
                                  SizedBox(width: 14),
                                  Text(
                                    '阅读',
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(left: 12, top: 14),
                              child: Text(
                                '让阅读，自由发生',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                            const SizedBox(height: 44),
                            for (var index = 0; index < _labels.length; index++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Material(
                                  color: _selected == index
                                      ? const Color(0xFFEEF0F3)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    key: Key('nav-$index'),
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => _select(index),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 15,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _icons[index],
                                            size: 21,
                                            color: _selected == index
                                                ? AppColors.ink
                                                : AppColors.muted,
                                          ),
                                          const SizedBox(width: 16),
                                          Text(
                                            _labels[index],
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: _selected == index
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: _selected == index
                                                  ? AppColors.ink
                                                  : AppColors.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 14),
                            Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                key: const Key('nav-sources'),
                                borderRadius: BorderRadius.circular(10),
                                onTap: _sources,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 15,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.language_outlined,
                                        size: 21,
                                        color: AppColors.muted,
                                      ),
                                      SizedBox(width: 16),
                                      Text(
                                        '书源管理',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '在书页之间，\n遇见自己。',
                                    style: TextStyle(
                                      fontSize: 17,
                                      height: 1.9,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 26),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.shield_outlined,
                                        size: 16,
                                        color: AppColors.muted,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '本地阅读 · ${widget.controller.books.length} 本书',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: content,
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : _TabBar(selected: _selected, onSelect: _select),
        );
      },
    ),
  );
}

/// 设计稿 `.tabbar`：白底、三项等宽、选中项蓝字并在图标下方点一个小圆点。
///
/// 用自绘而非 `NavigationBar`，因为稿里的选中态是「文字变蓝 + 4px 圆点」而不是
/// Material 的胶囊指示器；导航键 `nav-$index` 与宽屏侧栏保持一致。
class _TabBar extends StatelessWidget {
  const _TabBar({required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            for (var index = 0; index < _AppShellState._labels.length; index++)
              Expanded(
                child: InkWell(
                  key: Key('nav-$index'),
                  onTap: () => onSelect(index),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _AppShellState._icons[index],
                        size: 23,
                        color: selected == index
                            ? AppColors.blue
                            : const Color(0xFF999FA9),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _AppShellState._labels[index],
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.1,
                          fontWeight: selected == index
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selected == index
                              ? AppColors.blue
                              : const Color(0xFF999FA9),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: selected == index
                              ? AppColors.blue
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
