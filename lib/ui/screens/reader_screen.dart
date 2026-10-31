import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../domain/reader_settings.dart';
import '../components/common.dart';
import '../components/note_composer.dart';
import '../components/reader_preferences.dart';
import '../components/reader_toc_sheet.dart';
import '../reader/reader_paginator.dart';
import '../reader/reader_paragraph.dart';
import '../theme.dart';
import 'notes_screen.dart';

/// Keeps visible text and saved anchors tied to the current source binding.
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
  String? _bindingSourceId;
  String? _bindingChapterId;
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
  PageController? _pageController;
  ReaderPageLayout? _pageLayout;
  String? _pageLayoutKey;
  int _visiblePage = 0;
  bool _pagedFallback = false;

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

  // A source switch can replace the binding without starting this view's load.
  bool _matchesBinding(Book current) =>
      current.sourceId == _bindingSourceId &&
      _chapterIndex >= 0 &&
      _chapterIndex < current.chapters.length &&
      current.chapters[_chapterIndex].id == _bindingChapterId;

  bool _canUseLoad(int generation) {
    if (!mounted || generation != _generation) return false;
    final current = controller.book(widget.bookId);
    return current != null && _matchesBinding(current);
  }

  void _scheduleRestore(int anchor) {
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_canUseLoad(generation)) _restore(anchor);
    });
  }

  void _scheduleBindingReload() {
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      final current = controller.book(widget.bookId);
      if (current == null ||
          current.chapters.isEmpty ||
          _matchesBinding(current)) {
        return;
      }
      _pendingFinished = null;
      unawaited(
        _load(
          current.position.chapterIndex.clamp(0, current.chapters.length - 1),
          current.position.paragraphIndex,
        ),
      );
    });
  }

  Future<void> _load(int index, int paragraph) async {
    // 较早发起的请求可能较晚完成，不能覆盖用户后来选择的章节。
    final generation = ++_generation;
    final current = book;
    _saveTimer?.cancel();
    setState(() {
      _bindingSourceId = current.sourceId;
      _bindingChapterId = index >= 0 && index < current.chapters.length
          ? current.chapters[index].id
          : null;
      _loading = true;
      _restoring = true;
      _error = null;
      _chapterIndex = index;
      _requestedParagraphIndex = paragraph;
      _chapter = null;
      _pageLayout = null;
      _pageLayoutKey = null;
    });
    try {
      final chapter = await controller.chapter(widget.bookId, index);
      if (!_canUseLoad(generation)) return;
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
      _scheduleRestore(_paragraphIndex);
    } catch (error) {
      if (_canUseLoad(generation)) {
        setState(() {
          _loading = false;
          _error = errorMessage(error);
        });
      }
    }
  }

  void _restore(int index) {
    if (!mounted || _chapter == null) return;
    if (controller.settings.flow == ReaderFlow.paged && !_pagedFallback) {
      _paragraphIndex = index;
      _restoring = false;
      unawaited(_persist());
      return;
    }
    if (!_scroll.hasClients) return;
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
    if (controller.settings.flow == ReaderFlow.paged && !_pagedFallback) {
      return _paragraphIndex;
    }
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
    final current = controller.book(widget.bookId);
    if (current == null || !_matchesBinding(current)) return false;
    final generation = _generation;
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
      if (!_canUseLoad(generation)) return false;
      if (_pendingFinished == pendingFinished) _pendingFinished = null;
      if (mounted && _saveError != null) setState(() => _saveError = null);
      return true;
    } catch (_) {
      if (_canUseLoad(generation)) {
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
    _pageController?.dispose();
    super.dispose();
  }

  Widget _buildScrollingChapter({
    required double width,
    required Chapter chapter,
    required ReaderSettings settings,
    required Color ink,
    required Color muted,
  }) => SingleChildScrollView(
    key: const Key('reader-scrolling-view'),
    controller: _scroll,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            width < 650 ? 24 : 48,
            36,
            width < 650 ? 24 : 48,
            80,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chapter.title,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 26,
                  height: 1.6,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                book.isExcerpt ? '公版原文节选 · 已保存在本机' : '本章已缓存 · 可离线阅读',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 36),
              for (var index = 0; index < chapter.paragraphs.length; index++)
                Padding(
                  key: _paragraphKeys[index],
                  padding: EdgeInsets.only(bottom: settings.paragraphSpacing),
                  child: ReaderParagraph(
                    text: chapter.paragraphs[index],
                    selectable: true,
                    style: TextStyle(
                      inherit: false,
                      fontWeight: settings.boldText
                          ? FontWeight.bold
                          : FontWeight.w400,
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
                      ? (book.isExcerpt ? '本书节选至此，感谢阅读。' : '全文完。')
                      : '本章结束，继续下一章。',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _turnPage(int delta, int pageCount) async {
    final pages = _pageController;
    if (_loading ||
        _restoring ||
        pages == null ||
        !pages.hasClients ||
        pages.position.isScrollingNotifier.value) {
      return;
    }
    final target = ((pages.page ?? 0).round() + delta).clamp(0, pageCount - 1);
    await pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildPagedChapter({
    required Chapter chapter,
    required ReaderSettings settings,
    required Color ink,
    required Color muted,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontalPadding = constraints.maxWidth < 650 ? 24.0 : 48.0;
      final contentWidth = math.max(
        1.0,
        math.min(760.0, constraints.maxWidth) - horizontalPadding * 2,
      );

      final contentHeight = math.max(1.0, constraints.maxHeight - 12 - 28);
      final bodyStyle = TextStyle(
        inherit: false,
        fontFamily: 'NotoSansSC',
        fontSize: settings.fontSize,
        fontWeight: settings.boldText ? FontWeight.bold : FontWeight.w400,
        height: settings.lineHeight,
        color: ink,
      );
      final titleStyle = TextStyle(
        inherit: false,
        fontFamily: 'NotoSansSC',
        fontSize: 26,
        height: 1.6,
        fontWeight: FontWeight.w600,
        color: ink,
      );
      final titleMeasurement = TextPainter(
        text: TextSpan(text: chapter.title, style: titleStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: contentWidth);
      final minimumHeight =
          titleMeasurement.height +
          20 +
          settings.fontSize * settings.lineHeight;
      titleMeasurement.dispose();
      // Landscape and large accessibility text must remain readable, not crash.
      if (contentHeight < minimumHeight) {
        if (!_pagedFallback) {
          _pagedFallback = true;
          _scheduleRestore(_paragraphIndex);
        }
        return _buildScrollingChapter(
          width: constraints.maxWidth,
          chapter: chapter,
          settings: settings,
          ink: ink,
          muted: muted,
        );
      }
      if (_pagedFallback) _pageLayoutKey = null;
      _pagedFallback = false;
      final layoutKey =
          '${chapter.id}|${contentWidth.toStringAsFixed(1)}|'
          '${contentHeight.toStringAsFixed(1)}|${settings.fontSize}|'
          '${settings.lineHeight}|${settings.paragraphSpacing}|${settings.boldText}';
      if (_pageLayoutKey != layoutKey || _pageLayout == null) {
        final layout = ReaderPaginator.paginate(
          title: chapter.title,
          paragraphs: chapter.paragraphs,
          maxWidth: contentWidth,
          maxHeight: contentHeight,
          bodyStyle: bodyStyle,
          titleStyle: titleStyle,
          firstPageChromeHeight: 20,
          paragraphSpacing: settings.paragraphSpacing,
        );
        final leading = _chapterIndex > 0 ? 1 : 0;
        final contentPage = layout.pageForParagraph(_paragraphIndex);
        final oldController = _pageController;
        _pageController = PageController(initialPage: leading + contentPage);
        _pageLayout = layout;
        _pageLayoutKey = layoutKey;
        _visiblePage = contentPage;
        if (oldController != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => oldController.dispose(),
          );
        }
      }

      final layout = _pageLayout!;
      final pageController = _pageController!;
      final hasPrevious = _chapterIndex > 0;
      final hasNext = _chapterIndex + 1 < book.chapters.length;
      final leading = hasPrevious ? 1 : 0;
      final itemCount = layout.pages.length + leading + (hasNext ? 1 : 0);
      return Stack(
        children: [
          PageView.builder(
            key: const Key('reader-paged-view'),
            controller: pageController,
            itemCount: itemCount,
            onPageChanged: (index) {
              if (_loading || _restoring) return;
              if (hasPrevious && index == 0) {
                unawaited(_jump(_chapterIndex - 1));
                return;
              }
              final contentIndex = index - leading;
              if (hasNext && contentIndex == layout.pages.length) {
                unawaited(_jump(_chapterIndex + 1));
                return;
              }
              if (contentIndex < 0 || contentIndex >= layout.pages.length) {
                return;
              }
              final anchor = layout.pages[contentIndex].anchorParagraphIndex;
              if (_visiblePage != contentIndex || _paragraphIndex != anchor) {
                setState(() {
                  _visiblePage = contentIndex;
                  _paragraphIndex = anchor;
                });
              }
              _saveTimer?.cancel();
              _saveTimer = Timer(const Duration(milliseconds: 500), _persist);
            },
            itemBuilder: (context, index) {
              if (hasPrevious && index == 0) {
                return const Center(child: Text('正在打开上一章…'));
              }
              final contentIndex = index - leading;
              if (hasNext && contentIndex == layout.pages.length) {
                return const Center(child: Text('正在打开下一章…'));
              }
              final page = layout.pages[contentIndex];
              return Stack(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          12,
                          horizontalPadding,
                          28,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (page.showsChapterHeader) ...[
                              Text(
                                chapter.title,
                                style: titleStyle,
                                textScaler: TextScaler.noScaling,
                              ),
                              const SizedBox(height: 20),
                            ],
                            for (final fragment in page.fragments)
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: fragment.trailingSpacing,
                                ),
                                child: ReaderParagraph(
                                  text: fragment.text,
                                  isContinuation: fragment.isContinuation,
                                  style: bodyStyle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Row(
                      children: [
                        for (final direction in [-1, 0, 1])
                          Expanded(
                            child: direction == 0
                                ? const SizedBox.expand()
                                : Semantics(
                                    label: direction < 0 ? '上一页' : '下一页',
                                    button: true,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => unawaited(
                                        _turnPage(direction, itemCount),
                                      ),
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          Positioned(
            right: 16,
            bottom: 8,
            child: Text(
              '${_visiblePage + 1}/${layout.pages.length}',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final settings = controller.settings;
      final current = controller.book(widget.bookId);
      final bindingChanged =
          current != null &&
          current.chapters.isNotEmpty &&
          !_matchesBinding(current);
      if (bindingChanged) _scheduleBindingReload();
      final nextDisabled =
          _loading ||
          bindingChanged ||
          (_chapter == null && _chapterIndex + 1 == book.chapters.length);
      final dark = settings.theme == ReaderTheme.dark;
      final background = switch (settings.theme) {
        ReaderTheme.paper => const Color(0xFFF4EFDC),
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
                  onPressed: _chapter == null || bindingChanged
                      ? null
                      : _addNote,
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
                  _scheduleRestore(anchor);
                }
                _lastWidth = constraints.maxWidth;
                _lastFont = settings.fontSize;
                _lastHeight = settings.lineHeight;
                if (_loading || bindingChanged) {
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
                      child: settings.flow == ReaderFlow.scrolling
                          ? _buildScrollingChapter(
                              width: constraints.maxWidth,
                              chapter: chapter,
                              settings: settings,
                              ink: ink,
                              muted: muted,
                            )
                          : _buildPagedChapter(
                              chapter: chapter,
                              settings: settings,
                              ink: ink,
                              muted: muted,
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
    builder: (context) => ReaderTocSheet(
      book: book,
      currentChapterIndex: _chapterIndex,
      descending: controller.settings.tocDescending,
      onOrderChanged: (descending) => controller.updateSettings(
        controller.settings.copyWith(tocDescending: descending),
      ),
      onChapterSelected: (index) {
        Navigator.pop(context);
        unawaited(_jump(index));
      },
    ),
  );

  Future<void> _updateReaderSettings(ReaderSettings settings) async {
    final generation = _generation;
    final anchor = _visibleParagraph();
    await controller.updateSettings(settings);
    if (!_canUseLoad(generation)) return;
    setState(() {
      _paragraphIndex = anchor;
      _pageLayoutKey = null;
      _restoring = true;
    });
    _scheduleRestore(anchor);
  }

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
          onChanged: _updateReaderSettings,
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
