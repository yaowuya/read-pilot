import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../domain/reader_settings.dart';
import '../components/common.dart';
import '../components/note_composer.dart';
import '../components/reader_preferences.dart';
import '../theme.dart';
import 'notes_screen.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.controller,
    required this.bookId,
    this.initialPosition,
  });
  final AppController controller;
  final String bookId;
  final ReadingPosition? initialPosition;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  List<GlobalKey> _paragraphKeys = [];
  Chapter? _chapter;
  int _chapterIndex = 0;
  int _paragraphIndex = 0;
  int _requestedParagraphIndex = 0;
  int _generation = 0;
  bool _loading = true;
  bool _restoring = true;
  bool _leaving = false;
  bool _routePopped = false;
  bool? _pendingFinished;
  String? _error;
  String? _saveError;
  Timer? _saveTimer;
  double _lastWidth = 0;
  double _lastFont = 0;
  double _lastHeight = 0;

  AppController get controller => widget.controller;
  Book get book => controller.book(widget.bookId)!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    final position = widget.initialPosition ?? book.position;
    _load(
      position.chapterIndex.clamp(0, book.chapters.length - 1),
      position.paragraphIndex,
    );
  }

  Future<void> _load(int index, int paragraph) async {
    // 较早发起的请求可能较晚完成，不能覆盖用户后来选择的章节。
    final generation = ++_generation;
    _saveTimer?.cancel();
    setState(() {
      _loading = true;
      _restoring = true;
      _error = null;
      _chapterIndex = index;
      _requestedParagraphIndex = paragraph;
      _chapter = null;
    });
    try {
      final chapter = await controller.chapter(widget.bookId, index);
      if (!mounted || generation != _generation) return;
      setState(() {
        _chapter = chapter;
        _loading = false;
        _paragraphIndex = paragraph.clamp(0, chapter.paragraphs.length - 1);
        _paragraphKeys = List.generate(
          chapter.paragraphs.length,
          (_) => GlobalKey(),
        );
      });
      // 段落偏移依赖本轮布局；字号或视口变化后也要重新定位。
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _restore(_paragraphIndex),
      );
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = errorMessage(error);
        });
      }
    }
  }

  void _restore(int index) {
    if (!mounted || !_scroll.hasClients || _chapter == null) return;
    final target = _paragraphKeys[index.clamp(0, _paragraphKeys.length - 1)]
        .currentContext
        ?.findRenderObject();
    if (index == 0) {
      _scroll.jumpTo(0);
    } else if (target != null) {
      final offset = RenderAbstractViewport.of(
        target,
      ).getOffsetToReveal(target, 0).offset;
      _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
    }
    _paragraphIndex = index;
    _restoring = false;
    unawaited(_persist());
  }

  int _visibleParagraph() {
    if (_restoring || !_scroll.hasClients) return _paragraphIndex;
    var visible = 0;
    for (var index = 0; index < _paragraphKeys.length; index++) {
      final target = _paragraphKeys[index].currentContext?.findRenderObject();
      if (target == null) continue;
      final offset = RenderAbstractViewport.of(
        target,
      ).getOffsetToReveal(target, 0).offset;
      if (offset <= _scroll.offset + 12) {
        visible = index;
      } else {
        break;
      }
    }
    return visible;
  }

  void _onScroll() {
    if (_loading || _restoring) return;
    _paragraphIndex = _visibleParagraph();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _persist);
  }

  ReadingPosition get _currentPosition => ReadingPosition(
    chapterIndex: _chapterIndex,
    paragraphIndex: _paragraphIndex,
  );

  Future<bool> _persist({bool? finished}) async {
    _saveTimer?.cancel();
    // 完成标记失败后，重试和自动保存都必须保留原操作意图。
    if (finished != null) _pendingFinished = finished;
    if (_chapter == null || _loading) return _pendingFinished == null;
    final pendingFinished = _pendingFinished;
    try {
      await controller.savePosition(
        widget.bookId,
        _currentPosition,
        finished: pendingFinished,
      );
      if (_pendingFinished == pendingFinished) _pendingFinished = null;
      if (mounted && _saveError != null) setState(() => _saveError = null);
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _saveError = '阅读进度暂未保存，请检查本机存储空间。');
      }
      return false;
    }
  }

  Future<void> _retrySave() async {
    await _persist();
  }

  void _popReader() {
    // 路由退出动画期间仍然 mounted；迟到的保存完成不能再次弹出书架。
    if (!mounted || _routePopped) return;
    _routePopped = true;
    Navigator.of(context).pop();
  }

  void _discardAndLeave() {
    _leaving = true;
    _popReader();
  }

  Future<void> _markFinished() async {
    if (_loading || _chapter == null) return;
    if (await _persist(finished: true) && mounted) {
      showMessage(context, '又读完一本，下一本见。');
    }
  }

  Future<void> _jump(int chapterIndex, [int paragraph = 0]) async {
    if (_loading) return;
    if (!await _persist()) return;
    if (mounted) await _load(chapterIndex, paragraph);
  }

  Future<void> _leave() async {
    if (_leaving || _routePopped) return;
    _leaving = true;
    if (await _persist()) {
      _popReader();
    } else {
      _leaving = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_persist());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final settings = controller.settings;
      final nextDisabled =
          _loading ||
          (_chapter == null && _chapterIndex + 1 == book.chapters.length);
      final dark = settings.theme == ReaderTheme.dark;
      final background = switch (settings.theme) {
        ReaderTheme.paper => const Color(0xFFF4F0E6),
        ReaderTheme.light => const Color(0xFFFEFEFC),
        ReaderTheme.dark => const Color(0xFF1D1D1D),
      };
      final ink = dark ? const Color(0xFFD8D6D1) : const Color(0xFF34332F);
      final muted = dark ? const Color(0xFFAEACA7) : const Color(0xFF6E6B62);
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _leave();
        },
        child: Theme(
          data: Theme.of(context).copyWith(
            brightness: dark ? Brightness.dark : Brightness.light,
            iconTheme: IconThemeData(color: ink),
          ),
          child: Scaffold(
            backgroundColor: background,
            appBar: AppBar(
              backgroundColor: background,
              foregroundColor: ink,
              leading: IconButton(
                key: const Key('reader-back'),
                tooltip: '返回书架',
                onPressed: _leave,
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: ink,
                    ),
                  ),
                  Text(
                    '${book.author} · ${_chapterIndex + 1}/${book.chapters.length} 章',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  key: const Key('reader-bookmark'),
                  tooltip: '添加书签笔记',
                  onPressed: _chapter == null ? null : _addNote,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 23),
                ),
                IconButton(
                  tooltip: '本书笔记',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => NotesScreen(
                        controller: controller,
                        bookId: book.id,
                        onOpen: (note) {
                          Navigator.pop(context);
                          _jump(note.chapterIndex, note.paragraphIndex);
                        },
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.notes_outlined, size: 22),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                final changed =
                    _lastWidth != constraints.maxWidth ||
                    _lastFont != settings.fontSize ||
                    _lastHeight != settings.lineHeight;
                if (changed &&
                    !_loading &&
                    _chapter != null &&
                    _lastWidth != 0) {
                  final anchor = _visibleParagraph();
                  _restoring = true;
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _restore(anchor),
                  );
                }
                _lastWidth = constraints.maxWidth;
                _lastFont = settings.fontSize;
                _lastHeight = settings.lineHeight;
                if (_loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (_error != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            style: TextStyle(color: ink),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton(
                            onPressed: () =>
                                _load(_chapterIndex, _requestedParagraphIndex),
                            child: const Text('重新加载'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final chapter = _chapter!;
                return Column(
                  children: [
                    if (_saveError != null)
                      Container(
                        width: double.infinity,
                        color: dark
                            ? const Color(0xFF2C1A20)
                            : const Color(0xFFFFEDEA),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _saveError!,
                                style: TextStyle(
                                  color: dark
                                      ? const Color(0xFFE5566F)
                                      : const Color(0xFF831C1E),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            TextButton(
                              key: const Key('reader-save-retry'),
                              onPressed: _retrySave,
                              child: const Text('重试保存'),
                            ),
                            TextButton(
                              key: const Key('reader-discard-progress'),
                              onPressed: _discardAndLeave,
                              child: const Text('不保存退出'),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scroll,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                constraints.maxWidth < 650 ? 24 : 48,
                                36,
                                constraints.maxWidth < 650 ? 24 : 48,
                                80,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    chapter.title,
                                    style: TextStyle(
                                      fontSize: 26,
                                      height: 1.6,
                                      fontWeight: FontWeight.w600,
                                      color: ink,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    book.isExcerpt
                                        ? '公版原文节选 · 已保存在本机'
                                        : '本章已缓存 · 可离线阅读',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: muted,
                                    ),
                                  ),
                                  const SizedBox(height: 36),
                                  for (
                                    var index = 0;
                                    index < chapter.paragraphs.length;
                                    index++
                                  )
                                    Padding(
                                      key: _paragraphKeys[index],
                                      padding: const EdgeInsets.only(
                                        bottom: 20,
                                      ),
                                      child: SelectableText(
                                        chapter.paragraphs[index],
                                        style: TextStyle(
                                          fontFamily: 'NotoSansSC',
                                          fontSize: settings.fontSize,
                                          height: settings.lineHeight,
                                          color: ink,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 32),
                                  Center(
                                    child: Text(
                                      _chapterIndex + 1 == book.chapters.length
                                          ? (book.isExcerpt
                                                ? '本书节选至此，感谢阅读。'
                                                : '全文完。')
                                          : '本章结束，继续下一章。',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Container(
                color: background,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _loading || _chapterIndex == 0
                          ? null
                          : () => _jump(_chapterIndex - 1),
                      child: Text(
                        '‹ 上一章',
                        style: TextStyle(
                          color: _loading || _chapterIndex == 0
                              ? muted.withValues(alpha: .5)
                              : ink,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '章节目录',
                      onPressed: _showToc,
                      icon: Icon(
                        Icons.format_list_bulleted,
                        color: ink,
                        size: 22,
                      ),
                    ),
                    IconButton(
                      key: const Key('reader-settings'),
                      tooltip: '阅读设置',
                      onPressed: _showSettings,
                      icon: Icon(Icons.text_fields, color: ink, size: 24),
                    ),
                    TextButton(
                      key: const Key('reader-next'),
                      onPressed: nextDisabled
                          ? null
                          : () async {
                              if (_chapterIndex + 1 < book.chapters.length) {
                                await _jump(_chapterIndex + 1);
                              } else {
                                await _markFinished();
                              }
                            },
                      child: Text(
                        _chapterIndex + 1 < book.chapters.length
                            ? '下一章 ›'
                            : (book.finished ? '已读完 ✓' : '标记读完'),
                        style: TextStyle(color: ink, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  void _showToc() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => SizedBox(
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
                  '${book.chapters.length} 章',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: book.chapters.length,
              itemBuilder: (context, index) => ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 5,
                ),
                selected: index == _chapterIndex,
                selectedTileColor: AppColors.softBlue,
                title: Text(
                  book.chapters[index].title,
                  style: const TextStyle(fontSize: 14),
                ),
                trailing: index == _chapterIndex
                    ? const Icon(Icons.check, size: 19)
                    : (book.chapters[index].isCached
                          ? const Icon(
                              Icons.offline_pin_outlined,
                              size: 17,
                              color: AppColors.muted,
                            )
                          : null),
                onTap: () {
                  Navigator.pop(context);
                  _jump(index);
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void _showSettings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (context) => Theme(
      data: appTheme(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: ReaderPreferences(
          settings: controller.settings,
          onChanged: controller.updateSettings,
        ),
      ),
    ),
  );

  void _addNote() {
    _paragraphIndex = _visibleParagraph();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (context) => Theme(
        data: appTheme(),
        child: NoteComposer(
          controller: controller,
          book: book,
          chapterIndex: _chapterIndex,
          paragraphIndex: _paragraphIndex,
        ),
      ),
    );
  }
}
